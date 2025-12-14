package main

import la "lazytools/allocators"
import "core:fmt"
import "core:mem"
import "core:strings"

code := `
    ifx = {
        a = arg 0;
        op = arg 1;
        b = arg 2;
        ret = op a b;
    };

    b = ifx 5 + 5;
    _ = print b;
`

Function_Ref :: distinct string

Primitive :: union {
    Bool,
    Number,
    String,
    Function_Ref,
}

Function :: union {
    [dynamic]Statement,
    // args and super_args (the arguments of the containing function)
    proc([]Primitive, []Primitive) -> (Primitive, bool),
}

Scope :: struct {
    name: string,
    data: map[string]Primitive
}

DeepChainMap :: [dynamic]Scope

main :: proc() {
    afa: la.Auto_Free_Allocator
    ast_alloc := la.auto_free_allocator(&afa)
    defer free_all(ast_alloc)

    lexer := Lexer{data=transmute([]u8)code}
    parser := Parser{&lexer, make([dynamic]string, ast_alloc)}

    ast, ok := parse(&parser, ast_alloc)
    if !ok {
        for err in parser.errors {
            fmt.printfln("\x1b[31m%v\x1b[0m", err)
        }
        return
    }

    definitions := make(map[string]Function, ast_alloc)
    ok = collect_definitions(ast[:], &definitions, ast_alloc)
    if !ok do return

    // Add builtin functions
    definitions["global.+"] = proc(args: []Primitive, _: []Primitive) -> (Primitive, bool) {
        total := Number(0)
        for arg in args {
            num, ok := arg.(Number)
            if !ok {
                fmt.printfln("\x1b[31mRuntime Error function `+` only accepts ints, found %v\x1b[0m", arg)
                return nil, false
            }

            total += num
        }
        return total, true
    }

    definitions["global.print"] = proc(args: []Primitive, _: []Primitive) -> (Primitive, bool) {
        for arg in args {
            fmt.print(arg)
        }
        fmt.println()
        return nil, true
    }

    definitions["global.arg"] = proc(args: []Primitive, super: []Primitive) -> (Primitive, bool) {
        num := args[0]
        index := int(num.(Number))
        return super[index], true
    }

    // Create scopes
    deep_chain_map := make(DeepChainMap, ast_alloc)
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
                fmt.printfln("\x1b[31mSyntax Error duplicate name %v found\x1b[0m", name)
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
    namespace := "global"
) -> (Primitive, bool) {
    // each function gets its own AFA 
    afa: la.Auto_Free_Allocator
    context.allocator = la.auto_free_allocator(&afa)
    defer free_all()
    defer free_all(context.temp_allocator)

    append(dcm, Scope{namespace, make(map[string]Primitive)})
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
                fmt.printfln("\x1b[31mRuntime Error function %v not found\x1b[0m", call.function)
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

                    fmt.printfln("\x1b[31mRuntime Error variable %v not found\x1b[0m", arg)
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

            case proc([]Primitive, []Primitive) -> (Primitive, bool):
                // builtin function
                returned, ok = function(func_arguments[:], arguments)
            }

            if !ok {
                return nil, false
            }

            // Perform the assignment
            local_scope.data[string(call.name)] = returned
        }
    }

    if "ret" in local_scope.data {
        return local_scope.data["ret"]
    }
    pop(dcm)
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
