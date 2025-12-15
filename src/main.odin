package main

import la "lazytools/allocators"
import "core:fmt"
import "core:mem"
import "core:strings"
import os "core:os/os2"
import "base:runtime"

Function_Ref :: distinct string

Primitive :: union {
    Bool,
    Number,
    String,
    Function_Ref,
}

// Context for passing to builtin functions
Function_Context :: struct {
    definitions: map[string]Function,
    dcm: ^DeepChainMap,
    arguments: []Primitive,
    namespace: string,
}

// Generic function type encompassing builtin and user-defined functions
Function :: union {
    [dynamic]Statement,
    // args and super_args (the arguments of the containing function)
    proc([]Primitive, Function_Context) -> (Primitive, bool),
}

Scope :: struct {
    name: string,
    data: map[string]Primitive,
    alloc: mem.Allocator,
}

DeepChainMap :: [dynamic]Scope

// HACK: to prevent scopes basing their auto_free_allocators off of the previous
// scope's auto_free_allocators we store the base allocator here.
// So all the individual allocators are independent.
base_allocator: mem.Allocator

gc: GC_Data

main :: proc() {
    // Setup the tracking allocator when we run in debug mode
    when ODIN_DEBUG {
        fmt.println("Memory Tracking enabled")
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
        
		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

    base_allocator = context.allocator

    afa: la.Auto_Free_Allocator
    ast_alloc := la.auto_free_allocator(&afa)
    defer free_all(ast_alloc)

    // Read in the file
    if len(os.args) != 2 {
        fmt.println("usage: tetra filename")
    }
    filename := os.args[1]
    data := os.read_entire_file(filename, ast_alloc) or_else panic("Couldnt read file")

    lexer := Lexer{data=data}
    parser := Parser{&lexer, make([dynamic]string, ast_alloc)}

    ast, ok := parse(&parser, ast_alloc)
    if !ok {
        for err in parser.errors {
            error(err)
        }
        return
    }

    definitions := make(map[string]Function, ast_alloc)
    ok = collect_definitions(ast[:], &definitions, ast_alloc)
    if !ok do return
    register_builtins(&definitions)

    // Create scopes
    deep_chain_map := make(DeepChainMap, ast_alloc)
    // Create gc
    gc = make_gc()
    defer destroy_gc(&gc)

    // Finally execute the code
    execute(ast[:], definitions, &deep_chain_map, {})
}

collect_definitions :: proc(
    ast: []Statement,
    definitions: ^map[string]Function,
    allocator: mem.Allocator,
    namespace := "global"
) -> bool {
    context.allocator = allocator

    for stmt in ast {
        switch def in stmt {
        case Call:
            continue

        case Definition:
            builder := strings.builder_make()
            name := fmt.sbprintf(
                &builder,
                "%v.%v",
                namespace, def.name
            )

            if name in definitions {
                error("Syntax Error duplicate name %v found", name)
                return false
            }

            definitions[name] = def.statements

            collect_definitions(def.statements[:], definitions, allocator, name)
        }
    }

    return true
}

execute :: proc(
    ast: []Statement,
    definitions: map[string]Function,
    dcm: ^DeepChainMap,
    arguments: []Primitive,
    namespace := "global",
) -> (Primitive, bool) {
    // each function gets its own AFA 
    afa: la.Auto_Free_Allocator
    context.allocator = la.auto_free_allocator(&afa, base_allocator)
    defer free_all()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    // this runs after the local scope is destroyed
    // because defers are run in reverse order
    // this is important so that we actually clean stuff up!
    defer gc_collect(&gc, dcm^)

    append(dcm, Scope{namespace, make(map[string]Primitive), context.allocator})
    defer pop(dcm)
    local_scope := &dcm[len(dcm) - 1]

    for stmt in ast {
        switch call in stmt {
        // skip definitions because we've already got them
        case Definition:
            continue

        case Call:
            // Traverse the scopes to find the function
            func, full_name, found := find_func(definitions, dcm^, string(call.function))
            if !found {
                error("Runtime Error function %v not found", call.function)
                return nil, false
            }

            // Resolve the function's arguments into Primitives
            func_arguments := make([]Primitive, len(call.args), context.temp_allocator)
            for a, i in call.args {
                switch arg in a {
                case Bool: func_arguments[i] = arg
                case Number: func_arguments[i] = arg
                case String: func_arguments[i] = arg
                case Identifier:
                    // Search the scopes for the variable name
                    variable, found := find_var(dcm^, string(arg))
                    if found {
                        func_arguments[i] = variable
                        continue
                    }
                    
                    // attempt to find a function instead
                    _, variable, found = find_func(definitions, dcm^, string(arg))
                    if found {
                        func_arguments[i] = variable
                        continue
                    }

                    error("Runtime Error variable %v not found", arg)
                    return nil, false
                }
            }

            // Execute the fuction
            returned: Primitive
            ok: bool

            switch function in func {
            case [dynamic]Statement:
                returned, ok = execute(
                    function[:],
                    definitions,
                    dcm,
                    func_arguments[:],
                    string(full_name)
                )

            case proc([]Primitive, Function_Context) -> (Primitive, bool):
                // builtin function
                func_context := Function_Context{
                    definitions, dcm, arguments, namespace
                }
                returned, ok = function(func_arguments[:], func_context)
            }

            if !ok {
                return nil, false
            }

            // Perform the assignment
            // if the variable is ret we have special rules, it's always local
            if call.name != "ret" {
                // first check if the variable exists somewhere up the stack
                // if it does assign to that
                #reverse for &scope in dcm[:len(dcm)-1] {
                    if string(call.name) in scope.data {
                        scope.data[string(call.name)] = returned
                    }
                }
            }

            // otherwise just assign into the local scope
            local_scope.data[string(call.name)] = returned
        }
    }

    if "ret" in local_scope.data {
        ret := local_scope.data["ret"]

        if len(dcm) > 1 {
            if str, ok := ret.(String); ok {
                // clone the string into the parent scope
                //ret = String(strings.clone(string(str), dcm[len(dcm)-2].alloc))
                parent_scope := dcm[len(dcm) - 2]
                la.auto_free_move(raw_data(str), parent_scope.alloc)
            }
        }

        return ret, true
    }
    return nil, true
}

// Find the variable in the deep chain map
find_var :: proc(dcm: DeepChainMap, name: string) -> (Primitive, bool) {
    #reverse for scope in dcm {
        if name in scope.data {
            return scope.data[name], true
        }
    }

    return nil, false
}

// Find the function in defs
find_func :: proc(definitions: map[string]Function, dcm: DeepChainMap, name: string) -> (Function, Function_Ref, bool) {
    // Try find a Function_Ref first
    if full_name, found := find_var(dcm, name); found {
        if ref, ok := full_name.(Function_Ref); ok {
            return definitions[string(ref)], ref, true
        }
    }

    // Now look through defs normally
    #reverse for scope in dcm {
        full_name := fmt.tprintf("%v.%v", scope.name, name)
        if full_name in definitions {
            return definitions[full_name], Function_Ref(full_name), true
        }
    }

    return nil, "", false
}

// Show error messages nicely
error :: proc(format: string, args: ..any) {
    ff := fmt.tprintf("%v%v%v", "\x1b[31m", format, "\x1b[0m")
    fmt.printfln(ff, ..args)
}
