package main

import "core:mem"
import "core:strings"
import "core:sys/info"
import "core:fmt"

GC_Type :: enum {
    String,
    Group,
}

GC_Entry :: struct {
    marked: int,
    ptr: rawptr,
    type: GC_Type,
}

GC_Data :: struct {
    generation: int,
    last_size: f64,
    entries: [dynamic]GC_Entry,
}

make_gc :: proc() -> (out: GC_Data) {
    out.generation = 0
    out.last_size = 0
    out.entries = make([dynamic]GC_Entry, base_allocator)
    return
}

destroy_gc :: proc(gc: ^GC_Data) {
    for entry in gc.entries {
        if entry.type == .Group {
            g := cast(^Group)entry.ptr
            delete(g^)
        }

        free(entry.ptr)
    }

    delete(gc.entries)
}

gc_manage_str :: proc(gc: ^GC_Data, str: string) {
    entry := GC_Entry {
        marked = 0,
        ptr = raw_data(str),
        type = .String,
    }

    append(&gc.entries, entry)
}

gc_manage_group :: proc(gc: ^GC_Data, g: ^Group) {
    entry := GC_Entry {
        marked = 0,
        ptr = g,
        type = .Group,
    }

    append(&gc.entries, entry)
}

gc_collect :: proc(gc: ^GC_Data, dcm: DeepChainMap) {
    // Decide if we should run the GC
    current_memory := cap(gc.entries) * size_of(GC_Entry)
    allocated_since_last_gc := f64(current_memory) - gc.last_size

    // GC Policy (made up)
    // if we are using > 25% of total ram, do emergency GC
    // if the allocation size has grown by 50% since the last GC run, do a GC
    if current_memory < info.ram.total_ram / 4 {
        if allocated_since_last_gc < 256 do return // arbitrary
        if allocated_since_last_gc < 0.5 * f64(current_memory) do return
    }
    defer gc.last_size = f64(cap(gc.entries) * size_of(GC_Entry))

    gc.generation += 1

    // Mark
    for scope in dcm {
        for key, value in scope.data {
            mark(gc, value)
        }
    }

    // Sweep
    #reverse for entry, i in gc.entries {
        if entry.marked == gc.generation do continue

        if entry.type == .Group {
            g := cast(^Group)entry.ptr
            delete(g^)
        }

        free(entry.ptr, base_allocator)
        // This works because we're going backwards
        unordered_remove(&gc.entries, i)
    }

    // decide if to shrink
    used_size := len(gc.entries) * size_of(GC_Entry)
    cap_size := cap(gc.entries) * size_of(GC_Entry)
    if (used_size < cap_size / 2) && cap_size > 100 * mem.Megabyte {
        shrink(&gc.entries)
    }
}

@(private="file")
mark :: proc(gc: ^GC_Data, value: Primitive) {
    type: GC_Type
    ptr: rawptr

    #partial switch primitive in value {
    case String:
        ptr = raw_data(primitive)
        type = .String

    case ^Group:
        ptr = primitive
        type = .Group

        // Mark stuff nested in group
        for item in primitive {
            mark(gc, item)
        }

    case:
        return
    }

    // Perform the marking
    for &entry in gc.entries {
        if entry.type != type do continue
        if entry.ptr == ptr {
            entry.marked = gc.generation
            return
        }
    }
}
