package main

import "core:fmt"
import "core:strconv"
import "core:strings"

register_builtins :: proc(defs: ^map[string]Function) {
    defs["global.+"] = proc(args: []Primitive, _: Function_Context) -> (Primitive, bool) {
        total := Number(0)
        for arg in args {
            num, ok := arg.(Number)
            if !ok {
                error("Runtime Error function `+` only accepts numbers, found %v", arg)
                return nil, false
            }

            total += num
        }
        return total, true
    }

    defs["global.*"] = proc(args: []Primitive, _: Function_Context) -> (Primitive, bool) {
        total := Number(1)
        for arg in args {
            num, ok := arg.(Number)
            if !ok {
                error("Runtime Error function `+` only accepts numbers, found %v", arg)
                return nil, false
            }

            total *= num
        }
        return total, true
    }

    defs["global.-"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        // Do nothing
        if len(args) == 0 {
            return nil, true
        }

        all_args_are(args, Number, "-") or_return

        // Unary minus
        if len(args) == 1 {
            return -args[0].(Number), true
        }

        // General subtract
        total := args[0].(Number)
        for arg in args[1:] {
            total -= arg.(Number)
        }

        return total, true
    }

    defs["global./"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        // Do nothing
        if len(args) == 0 {
            return nil, true
        }

        all_args_are(args, Number, "/") or_return

        // General divide
        total := args[0].(Number)
        for arg in args[1:] {
            total /= arg.(Number)
        }

        return total, true
    }

    defs["global.print"] = proc(args: []Primitive, _: Function_Context) -> (Primitive, bool) {
        for arg in args {
            fmt.print(arg)
        }
        fmt.println()
        return nil, true
    }

    defs["global.arg"] = proc(args: []Primitive, super: Function_Context) -> (Primitive, bool) {
        if len(args) != 1 {
            error("Runtime Error function `arg` only accepts one argument")
            return nil, false
        }
        num := args[0]

        index, ok := num.(Number)
        if !ok {
            error("Runtime Error function `arg` only accepts numbers, found %v", num)
            return nil, false
        }

        // TODO: decide on behaviour when out of bounds access
        return super.arguments[int(index)], true
    }

    defs["global.if"] = proc(args: []Primitive, super: Function_Context) -> (out: Primitive, ok: bool) {
        all_args_are(args, Function_Ref, "if") or_return

        if len(args) < 2 || len(args) > 3 {
            error("Runtime Error function `if` only accepts two arguments.\nUsage: if cond then [else]")
        }
        
        cond := execute_func(args[0], super) or_return

        ret: Primitive

        if cond == Bool(true) {
            ret = execute_func(args[1], super) or_return
        } else if len(args) == 3 {
            // else case
            ret = execute_func(args[2], super) or_return
        }

        return ret, true
    }

    defs["global.for"] = proc(args: []Primitive, super: Function_Context) -> (Primitive, bool) {
        if len(args) != 3 {
            error("Runtime Error function `for` requires 3 arguments.\nUsage: for start end func")
            return nil, false
        }

        start, ok := args[0].(Number)
        if !ok {
            error("Runtime Error function `for` only accepts number for arg 0.")
            return nil, false
        }

        end, ok2 := args[1].(Number)
        if !ok {
            error("Runtime Error function `for` only accepts number for arg 1.")
            return nil, false
        }

        func, ok3 := args[2].(Function_Ref)
        if !ok {
            error("Runtime Error function `for` only accepts function for arg 2.")
            return nil, false
        }

        ret: Primitive
        for i in int(start)..<int(end) {
            ret, ok = execute_func(func, super, {Number(i)})
            if !ok do return nil, false
        }

        return ret, true
    }

    defs["global.bool"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        all_args_are(args, Bool, "bool") or_return
        return args[0].(Bool), true
    }

    defs["global.num"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 1 {
            error("Runtime Error function `num` only accepts 1 argument")
            return nil, false
        }

        switch arg in args[0] {
        case Bool:
            if arg == Bool(true) {
                return Number(1), true
            } else {
                return Number(0), true
            }

        case String:
            num, ok := strconv.parse_f64(string(arg)) 
            if !ok {
                error("Runtmie Error function `num` cannot parse String \"%v\"", arg)
                return nil, false
            }
            return Number(num), true

        case Number:
            return arg, true

        case Function_Ref:
            error("Runtime Error function `num` cannot convert function `%v` into Number", arg)
            return nil, false
        }

        panic("Impossible")
    }


    defs["global.str"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        builder := strings.builder_make(base_allocator)

        for arg in args {
            fmt.sbprintf(&builder, "%v", arg)
        }

        str := strings.to_string(builder)
        gc_manage_str(&gc, str)
        return String(str), true
    }

}

// Helpers
@(private="file")
all_args_are :: proc(args: []Primitive, $T: typeid, from: string) -> bool {
    for arg in args {
        if _, ok := arg.(T); !ok {
            error(
                "Runtime Error function `%v` only accepts %v, found %v",
                from, typeid_of(T), arg
            )
            return false
        }
    }
    return true
}

@(private="file")
execute_func :: proc(
    ref: Primitive,
    super: Function_Context,
    args: []Primitive = nil
) -> (Primitive, bool) {
    ref := ref.(Function_Ref)
    if string(ref) not_in super.definitions {
        error("Runtime Error function %v not found", ref)
        return nil, false
    }
    func := super.definitions[string(ref)]

    args := args
    if args == nil {
        args = []Primitive{}
    }

    switch raw_fn in func {
    case proc([]Primitive, Function_Context) -> (Primitive, bool):
        return raw_fn(args, super)

    case [dynamic]Statement:
        return execute(raw_fn[:], super.definitions, super.dcm, args, string(ref))
    }

    panic("Impossible")
}
