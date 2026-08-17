// ave_probe6.c — fine-grained IO_Open probing with correct codecType field
// AVE_Open_UserKernel_In_Info: pIn+0x10 = codecType (must be < 2)
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

static void test_sel(io_connect_t conn, int sel, size_t in_sz, size_t out_sz,
                     int codec_type, unsigned int w, unsigned int h, const char *tag) {
    unsigned char *inbuf = calloc(1, in_sz + 64);
    unsigned char *outbuf = calloc(1, out_sz + 64);
    *(unsigned int*)(inbuf + 0x10) = (unsigned int)codec_type;   // codecType < 2
    *(unsigned int*)(inbuf + 0x14) = 0;
    // try to find width/height: put in various offsets
    if (in_sz > 0x20) {
        *(unsigned int*)(inbuf + 0x18) = w;
        *(unsigned int*)(inbuf + 0x1c) = h;
    }
    size_t osz = out_sz;
    kern_return_t kr = IOConnectCallStructMethod(conn, sel, inbuf, in_sz, outbuf, &osz);
    printf("  [%s] sel %d in=%zu out=%zu codec=%d w/h@0x18: kr=0x%x outsz=%zu out0=0x%x out1=0x%x\n",
           tag, sel, in_sz, out_sz, codec_type, kr, osz,
           *(unsigned int*)outbuf, *(unsigned int*)(outbuf+4));
    fflush(stdout);
    free(inbuf);
    free(outbuf);
}

int main(void) {
    unsigned int iter = 0;
    kern_return_t kr = IOServiceGetMatchingServices(0, IOServiceMatching("AppleAVE2Driver"), &iter);
    if (kr || !iter) { printf("no service kr=%d\n", kr); return 1; }
    io_service_t svc = IOIteratorNext(iter);
    io_connect_t conn = 0;
    kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    printf("open kr=0x%x conn=%u\n", kr, conn);
    if (kr || !conn) return 1;

    printf("=== IO_Open (sel 0) with codecType=0/1, various sizes ===\n");
    test_sel(conn, 0, 1232, 8, 0, 0, 0, "AVC");
    test_sel(conn, 0, 1232, 8, 1, 0, 0, "HEVC");
    test_sel(conn, 0, 2048, 8, 0, 0, 0, "bigger");
    test_sel(conn, 0, 4096, 16, 0, 0, 0, "4096");

    printf("=== width/height at 0x18/0x1c with codec=0 ===\n");
    test_sel(conn, 0, 1232, 8, 0, 65537, 65537, "wh0x18");

    printf("=== sel 3 IO_Prepare / sel 4 IO_Start with codec at 0x10 ===\n");
    test_sel(conn, 3, 236656, 4, 0, 0, 0, "prepare");
    test_sel(conn, 4, 236656, 4, 0, 0, 0, "start");

    IOServiceClose(conn);
    printf("=== done ===\n");
    return 0;
}
