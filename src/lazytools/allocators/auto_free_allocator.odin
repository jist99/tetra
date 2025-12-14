package allocators

import "core:mem"
import "core:testing"
import "core:log"
import "base:runtime"

/*
An allocator for lazy programmers.

Maintains a list of all allocations made using this allocator, when free_all() is called
the allocator will call the backing allocator's free function on every tracked allocation.

Useful if you have a structure of dynamic data structures that you're too lazy
to traverse through to free.

Example:

    import la "lazytools/allocators"

    example :: proc() {
        alloc: la.Auto_Free_Allocator
        context.allocator = la.auto_free_allocator(&alloc)

        // Make some allocations

        free_all()
    }
*/
Auto_Free_Allocator :: struct {
    backing_allocator: mem.Allocator,
    allocations: [dynamic]rawptr, // Maybe this could be a hashset?
    tracking: bool, // If this is false then we need to allocate our array
}

/*
Initialises an auto free allocator, returning a mem.Allocator
*/
auto_free_allocator :: proc(lazy: ^Auto_Free_Allocator, allocator := context.allocator) -> (out: mem.Allocator) {
    lazy.backing_allocator = allocator

    out.data = auto_cast lazy
    out.procedure = auto_free_allocator_proc
    return
}

auto_free_allocator_proc :: proc(
    allocator_data: rawptr,
    mode: mem.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr,
    old_size: int,
    location := #caller_location
) -> ([]u8, mem.Allocator_Error) {
    lazy_alloc := cast(^Auto_Free_Allocator) allocator_data
    
    if !lazy_alloc.tracking {
        lazy_alloc.allocations = make([dynamic]rawptr, allocator=lazy_alloc.backing_allocator)
        lazy_alloc.tracking = true
    }


    switch mode {
    case .Alloc, .Alloc_Non_Zeroed:
        data, err := lazy_alloc.backing_allocator.procedure(
            auto_cast lazy_alloc.backing_allocator.data,
            mode, size, alignment, old_memory, old_size,
            location = location,
        )
        if err != .None do return nil, err

        append(&lazy_alloc.allocations, raw_data(data))
        return data, nil

    case .Free:
        data, err := lazy_alloc.backing_allocator.procedure(
            auto_cast lazy_alloc.backing_allocator.data,
            mode, size, alignment, old_memory, old_size,
            location = location,
        )
        if err != .None do return nil, err
        
        // find the index of the allocation
        index: int
        found := false
        for ptr, i in lazy_alloc.allocations {
            if ptr == old_memory {
                index = i
                found = true
                break
            }
        }

        if !found do return nil, .Invalid_Pointer

        unordered_remove(&lazy_alloc.allocations, index)
        return data, nil

    case .Free_All:
        err: mem.Allocator_Error
        for allocation in lazy_alloc.allocations {
            err = free(allocation, allocator=lazy_alloc.backing_allocator, loc=location)
        }
        if err != .None do return nil, err

        err = delete(lazy_alloc.allocations)
        lazy_alloc.tracking = false
        if err != .None do return nil, err

        return nil, nil

    case .Resize, .Resize_Non_Zeroed:
        // find the index of the allocation
        index: int
        found := false
        for ptr, i in lazy_alloc.allocations {
            if ptr == old_memory {
                index = i
                found = true
                break
            }
        }

        if !found do return nil, .Invalid_Pointer

        data, err := lazy_alloc.backing_allocator.procedure(
            auto_cast lazy_alloc.backing_allocator.data,
            mode, size, alignment, old_memory, old_size,
            location = location,
        )
        if err != .None do return nil, err

        lazy_alloc.allocations[index] = raw_data(data)

        return data, nil

    case .Query_Features:
        set := (^mem.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {.Query_Features, .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed, .Free, .Free_All, .Query_Info}
		}
        return nil, nil

    case .Query_Info:
        return nil, .Mode_Not_Implemented
    }

    return nil, nil
}
