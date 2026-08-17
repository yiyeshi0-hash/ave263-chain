// ave_probe5.c — exact IOExternalMethodDispatch sizes for A11 AppleAVE2Driver
// sel 0: IO_Open    structIn=1232   structOut=8
// sel 1: IO_Close   structIn=24     structOut=4
// sel 2: SetCallback structIn=40    structOut=4
// sel 3: IO_Prepare structIn=236656 structOut=4
// sel 4: IO_Start   structIn=236656 structOut=4
// sel 5: IO_Stop    structIn=24     structOut=4
// sel 6: IO_Complete structIn=24    structOut=4
// sel 7: IO_Process structIn=32     structOut=4
// sel 8: IO_Reset   structIn=24     structOut=4
// KEY FIX: outbuf size must EXACTLY match dispatch->checkStructureOutputSize
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <mach/mach.h>

typedef unsigned int io_service_t;
typedef unsigned int io_connect_t;
typedef int kern_return_t;

extern kern_return_t IOServiceGetMatchingServices(mach_port_t, void*, unsigned int*);
extern void* IOServiceMatching(const char*);
extern kern_return_t IOIteratorNext(unsigned int);
extern kern_return_t IOServiceOpen(io_service_t, mach_port_t, unsigned int, io_connect_t*);
extern kern_return_t IOServiceClose(io_connect_t);
extern kern_return_t IOObjectRelease(unsigned int);
extern kern_return_t IOConnectCallStructMethod(io_connect_t, unsigned int, const void*, size_t, void*, size_t*);

static const size_t IN_SIZES[9] = {1232, 24, 40, 236656, 236656, 24, 24, 32, 24};
static const size_t OUT_SIZES[9] = {8, 4, 4, 4, 4, 4, 4, 4, 4};

int main(void) {
    unsigned int iter = 0;
    kern_return_t kr = IOServiceGetMatchingServices(0, IOServiceMatching("AppleAVE2Driver"), &iter);
    if (kr || !iter) { printf("no service kr=%d\n", kr); return 1; }
    io_service_t svc = IOIteratorNext(iter);
    io_connect_t conn = 0;
    kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    printf("open kr=0x%x conn=%u\n", kr, conn);
    if (kr || !conn) return 1;

    for (int sel = 0; sel < 9; sel++) {
        size_t in_sz = IN_SIZES[sel];
        size_t out_sz = OUT_SIZES[sel];
        unsigned char *inbuf = calloc(1, in_sz);
        unsigned char *outbuf = calloc(1, out_sz + 16); // extra padding ok, we pass exact out_sz
        // width/height at offset 0 and 0x10
        *(unsigned int*)(inbuf + 0) = 65537;
        *(unsigned int*)(inbuf + 4) = 65537;
        if (in_sz > 0x14) {
            *(unsigned int*)(inbuf + 0x10) = 65537;
            *(unsigned int*)(inbuf + 0x14) = 65537;
        }
        size_t outsz = out_sz;
        kern_return_t prk = IOConnectCallStructMethod(conn, sel, inbuf, in_sz, outbuf, &outsz);
        printf("sel %d (in=%zu out=%zu): kr=0x%x outsz=%zu out0=0x%x\n", sel, in_sz, out_sz, prk, outsz,
               *(unsigned int*)outbuf);
        fflush(stdout);
        free(inbuf);
        free(outbuf);
    }
    IOServiceClose(conn);
    printf("=== done ===\n");
    return 0;
}
