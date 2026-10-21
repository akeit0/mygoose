/* A private native dispatch stack, on the existing AppKit thread. Only the
   callee-saved machine state crosses a switch; no Goose callbacks or threads.
   Keep the stack bootstrap here rather than using deprecated ucontext APIs. */
#ifndef MYGOOSE_MACOS_CONTEXT_H
#define MYGOOSE_MACOS_CONTEXT_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <sys/mman.h>
#include <unistd.h>

#if defined(__arm64__) && !defined(__arm64e__)
typedef struct {
    uint64_t x[12], sp, fpcr, fpsr, padding, d[8];
} mg_context;
_Static_assert(offsetof(mg_context,sp)==96 && offsetof(mg_context,d)==128,"ARM64 context layout");
static __attribute__((naked,noinline)) void mg_context_swap(mg_context *from __attribute__((unused)),const mg_context *to __attribute__((unused))) {
    __asm__ volatile(
        "stp x19,x20,[x0,#0]\n stp x21,x22,[x0,#16]\n"
        "stp x23,x24,[x0,#32]\n stp x25,x26,[x0,#48]\n"
        "stp x27,x28,[x0,#64]\n stp x29,x30,[x0,#80]\n"
        "mov x2,sp\n mrs x3,fpcr\n stp x2,x3,[x0,#96]\n"
        "mrs x2,fpsr\n str x2,[x0,#112]\n"
        "stp d8,d9,[x0,#128]\n stp d10,d11,[x0,#144]\n"
        "stp d12,d13,[x0,#160]\n stp d14,d15,[x0,#176]\n"
        "ldp x19,x20,[x1,#0]\n ldp x21,x22,[x1,#16]\n"
        "ldp x23,x24,[x1,#32]\n ldp x25,x26,[x1,#48]\n"
        "ldp x27,x28,[x1,#64]\n ldp x29,x30,[x1,#80]\n"
        "ldp x2,x3,[x1,#96]\n mov sp,x2\n msr fpcr,x3\n"
        "ldr x2,[x1,#112]\n msr fpsr,x2\n"
        "ldp d8,d9,[x1,#128]\n ldp d10,d11,[x1,#144]\n"
        "ldp d12,d13,[x1,#160]\n ldp d14,d15,[x1,#176]\n ret\n");
}
static void mg_context_init(mg_context *context,void *top,void (*entry)(void)) {
    *context=(mg_context){0}; context->sp=(uintptr_t)top; context->x[11]=(uintptr_t)entry;
    __asm__ volatile("mrs %0,fpcr\n mrs %1,fpsr" : "=r"(context->fpcr),"=r"(context->fpsr));
}
#elif defined(__x86_64__)
typedef struct { uint64_t rbp,rbx,r12,r13,r14,r15,rsp,rip; uint32_t mxcsr; uint16_t x87cw; } mg_context;
_Static_assert(offsetof(mg_context,rsp)==48 && offsetof(mg_context,mxcsr)==64,"x86-64 context layout");
static __attribute__((naked,noinline)) void mg_context_swap(mg_context *from __attribute__((unused)),const mg_context *to __attribute__((unused))) {
    __asm__ volatile(
        "movq %rbp,0(%rdi)\n movq %rbx,8(%rdi)\n"
        "movq %r12,16(%rdi)\n movq %r13,24(%rdi)\n"
        "movq %r14,32(%rdi)\n movq %r15,40(%rdi)\n"
        "movq %rsp,48(%rdi)\n leaq 1f(%rip),%rax\n movq %rax,56(%rdi)\n"
        "stmxcsr 64(%rdi)\n fnstcw 68(%rdi)\n"
        "movq 0(%rsi),%rbp\n movq 8(%rsi),%rbx\n"
        "movq 16(%rsi),%r12\n movq 24(%rsi),%r13\n"
        "movq 32(%rsi),%r14\n movq 40(%rsi),%r15\n"
        "ldmxcsr 64(%rsi)\n fldcw 68(%rsi)\n"
        "movq 48(%rsi),%rsp\n jmpq *56(%rsi)\n 1: retq\n");
}
static void mg_context_init(mg_context *context,void *top,void (*entry)(void)) {
    *context=(mg_context){0}; context->rsp=(uintptr_t)top-8; context->rip=(uintptr_t)entry;
    *(uint64_t *)context->rsp=0; // A normal SysV function entry is 8 mod 16.
    __asm__ volatile("stmxcsr %0\n fnstcw %1" : "=m"(context->mxcsr),"=m"(context->x87cw));
}
#else
#error MyGoose native dispatch supports macOS arm64 and x86_64
#endif

typedef struct { void *mapping; size_t size; mg_context caller,dispatch; } mg_dispatch_stack;
static bool mg_stack_create(mg_dispatch_stack *stack,void (*entry)(void)) {
    size_t page=(size_t)sysconf(_SC_PAGESIZE), usable=2*1024*1024;
    size_t size=usable+2*page;
    void *mapping=mmap(NULL,size,PROT_NONE,MAP_PRIVATE|MAP_ANON,-1,0);
    if (mapping==MAP_FAILED) return false;
    if (mprotect((char *)mapping+page,usable,PROT_READ|PROT_WRITE)) { munmap(mapping,size); return false; }
    stack->mapping=mapping; stack->size=size;
    mg_context_init(&stack->dispatch,(char *)mapping+page+usable,entry);
    return true;
}
static void mg_stack_destroy(mg_dispatch_stack *stack) {
    if (stack->mapping) munmap(stack->mapping,stack->size);
    *stack=(mg_dispatch_stack){0};
}
#endif
