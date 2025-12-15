package main

import "core:mem"
import "core:strings"

GC_Type :: enum {
    String,
}

GC_Entry :: struct {
    marked: int,
    ptr: rawptr,
    type: GC_Type,
}

GC_Data :: struct {
    generation: int,
    entries: [dynamic]GC_Entry,
}

make_gc :: proc() -> (out: GC_Data) {
    out.generation = 0
    out.entries = make([dynamic]GC_Entry, base_allocator)
    return
}

destroy_gc :: proc(gc: ^GC_Data) {
    for entry in gc.entries {
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

gc_collect :: proc(gc: ^GC_Data, dcm: DeepChainMap) {
    // Arbitrary choice
    if len(gc.entries) < 2000 {
        return
    }

    gc.generation += 1

    // Mark
    for scope in dcm {
        for key, value in scope.data {
            #partial switch primitive in value {
            case String:
                mark(gc, raw_data(primitive), .String)

            case:
                continue
            }
        }
    }

    // Sweep
    #reverse for entry, i in gc.entries {
        if entry.marked == gc.generation do continue

        free(entry.ptr, base_allocator)
        // This works because we're going backwards
        unordered_remove(&gc.entries, i)
    }
}

@(private="file")
mark :: proc(gc: ^GC_Data, ptr: rawptr, type: GC_Type) {
    for &entry in gc.entries {
        if entry.type != type do continue
        if entry.ptr == ptr {
            entry.marked = gc.generation
        }
    }
}
