package test

import la "../../allocators"
import "core:testing"

@test
test_tracking :: proc(t: ^testing.T) {
    a: la.Auto_Free_Allocator
    lazy := la.auto_free_allocator(&a)

    testing.expect(t, len(a.allocations) == 0)
    testing.expect(t, a.tracking == false)

    i := new(int, allocator=lazy)

    testing.expect(t, len(a.allocations) == 1)
    testing.expect(t, a.tracking == true)

    free_all(lazy)

    testing.expect(t, a.tracking == false)
}

@test
test_multi_tracking :: proc(t: ^testing.T) {
    a: la.Auto_Free_Allocator
    context.allocator = la.auto_free_allocator(&a)

    testing.expect(t, len(a.allocations) == 0)

    arr := make([dynamic]int)
    append(&arr, 1)
    append(&arr, 2)

    arr2 := make([dynamic]f32)
    append(&arr2, 1.5)

    testing.expect(t, len(a.allocations) == 2)

    free_all()
}

@test
test_realloc :: proc(t: ^testing.T) {
    a: la.Auto_Free_Allocator
    context.allocator = la.auto_free_allocator(&a)

    testing.expect(t, len(a.allocations) == 0)

    arr := make([dynamic]int)
    append(&arr, 12)
    resize(&arr, 100)

    free_all()
}
