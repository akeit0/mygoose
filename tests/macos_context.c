#include "../native/macos/context.h"
#include <assert.h>
#include <fenv.h>
#include <stdio.h>
static mg_dispatch_stack stack;
static int sequence;
static void dispatch(void) {
    volatile int local=42;
    uintptr_t address=(uintptr_t)&local;
    assert(address>(uintptr_t)stack.mapping && address<(uintptr_t)stack.mapping+stack.size);
    fesetround(FE_DOWNWARD);
    for (int i=0;;i++) {
        assert(sequence==i*2 && local==42 && fegetround()==FE_DOWNWARD);
        sequence++;
        mg_context_swap(&stack.dispatch,&stack.caller);
    }
}
int main(void) {
    fesetround(FE_UPWARD);
    assert(mg_stack_create(&stack,dispatch));
    volatile int caller_local=123;
    for (int i=0;i<10000;i++) {
        assert(sequence==i*2 && caller_local==123);
        mg_context_swap(&stack.caller,&stack.dispatch);
        assert(sequence==i*2+1 && caller_local==123 && fegetround()==FE_UPWARD);
        sequence++;
    }
    fesetround(FE_TONEAREST); mg_stack_destroy(&stack);
    assert(!stack.mapping);
    puts("PASS: native stack bounds/lifecycle, 10000 context round trips, caller state and independent floating-point modes");
}
