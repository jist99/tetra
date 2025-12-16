package main

import "core:fmt"
import "core:strconv"
import "core:strings"

register_builtins :: proc(defs: ^map[string]Function) {
    defs["global.return"] = Return_Func{}

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

    // We want to call eq from other builtins, so define it seperately
    defs["global.eq"] = equality
    equality :: proc(args: []Primitive, _: Function_Context) -> (Primitive, bool) {
        if len(args) < 2 {
            error("Runtime Error function `eq` requires two or more arugments.")
            return nil, false
        }

        // This can be massively simplified since we can just do
        // a direct ==
        // But I've written this now so we'll live with it for now
        all_equal :: proc(base: $T, args: []Primitive) -> Bool {
            for arg in args[1:] {
                item, ok := arg.(T)
                if !ok {
                    return Bool(false)
                }
                if base != item {
                    return Bool(false)
                }
            }
            return Bool(true)
        }

        group_equality :: proc(group: ^Group, other: ^Group) -> Bool {
            if len(group) != len(other) {
                return Bool(false)
            }

            for i in 0 ..< len(group) {
                sub_group, ok := group[i].(^Group)
                other_sub, ok2 := other[i].(^Group)
                equal: Bool
                if ok && ok2 {
                    equal = group_equality(sub_group, other_sub)
                } else if !ok && !ok2 {
                    equal = group[i] == other[i]
                } else {
                    return Bool(false)
                }
                if equal == Bool(false) do return Bool(false)
            }

            return Bool(true)
        }

        switch base in args[0] {
        case String:
            return all_equal(base, args), true

        case Bool:
            return all_equal(base, args), true

        case Number:
            return all_equal(base, args), true

        case Function_Ref:
            return all_equal(base, args), true

        case ^Group:
            for item in args[1:] {
                group, ok := item.(^Group)
                if !ok {
                    return Bool(false), true
                }
                if group_equality(base, group) == Bool(false) {
                    return Bool(false), true
                }
            }
            return Bool(true), true
        }

        panic("Impossible")
    }

    defs["global.neq"] = proc(args: []Primitive, _: Function_Context) -> (Primitive, bool) {
        value, ok := equality(args, Function_Context{})
        if !ok {
            return nil, false
        }
        boolean := value.(Bool)
        return Bool(!bool(boolean)), true
    }

    defs["global.>"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 2 {
            error("Runtime Error function `>` only accepts two arguments\nUsage: > num num")
        }
        all_args_are(args, Number, ">") or_return

        left := args[0].(Number)
        right := args[1].(Number)

        return Bool(left > right), true
    }

    defs["global.>="] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 2 {
            error("Runtime Error function `>=` only accepts two arguments\nUsage: >= num num")
        }
        all_args_are(args, Number, ">=") or_return

        left := args[0].(Number)
        right := args[1].(Number)

        return Bool(left >= right), true
    }

    defs["global.<"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 2 {
            error("Runtime Error function `<` only accepts two arguments\nUsage: < num num")
        }
        all_args_are(args, Number, "<") or_return

        left := args[0].(Number)
        right := args[1].(Number)

        return Bool(left < right), true
    }

    defs["global.<="] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 2 {
            error("Runtime Error function `<=` only accepts two arguments\nUsage: <= num num")
        }
        all_args_are(args, Number, "<=") or_return

        left := args[0].(Number)
        right := args[1].(Number)

        return Bool(left <= right), true
    }

    defs["global.print"] = proc(args: []Primitive, _: Function_Context) -> (Primitive, bool) {
        for arg in args {
            if group, ok := arg.(^Group); ok {
                fmt.print("[", group[0], sep="", flush=false)

                for item in group[1:] {
                    fmt.print(",", item, flush=false)
                }

                fmt.print("] ")
                continue
            }

            fmt.print(arg, flush=false)
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
        cond_satisfied := false
        if b, ok := cond.(Bool); ok {
            cond_satisfied = bool(b)
        }

        ret: Primitive
        if cond_satisfied {
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
        if !ok2 {
            error("Runtime Error function `for` only accepts number for arg 1.")
            return nil, false
        }

        func, ok3 := args[2].(Function_Ref)
        if !ok3 {
            error("Runtime Error function `for` only accepts function for arg 2.")
            return nil, false
        }

        broken := false
        for i in int(start)..<int(end) {
            ret, ok := execute_func(func, super, {Number(i)})
            if !ok do return nil, false

            if ret == nil do ret = Bool(true)
            boolean, ok2 := ret.(Bool)
            if !ok2 {
                error(
                    "Runtime Error iter function within `for` `%v` may only return Bool. Got %v.\nTrue = continue iterating, False = break iteration",
                    func, ret
                )
                return nil, false
            }

            if boolean == Bool(false) {
                broken = true
                break
            }
        }

        return Bool(broken), true
    }

    defs["global.while"] = proc(args: []Primitive, super: Function_Context) -> (Primitive, bool) {
        if len(args) != 2 {
            error("Runtime Error function `while` requires 2 arguments.\nUsage: while cond func")
            return nil, false
        }

        cond, ok := args[0].(Function_Ref)
        if !ok {
            error("Runtime Error function `while` only accepts function for arg 0.")
            return nil, false
        }

        func, ok2 := args[1].(Function_Ref)
        if !ok2 {
            error("Runtime Error function `while` only accepts function for arg 1.")
            return nil, false
        }

        broken := false
        for {
            // check the condition on the while loop
            if cond, ok := execute_func(cond, super, {}); ok {
                boolean, ok2 := cond.(Bool)
                if !ok2 {
                    error(
                        "Runtime Error cond function `%v` within while may only return Bool. Got %v.",
                        func, cond
                    )
                    return nil, false
                }

                if boolean == Bool(false) do break
            }

            // execute the iter function
            ret, ok := execute_func(func, super, {})
            if !ok do return nil, false

            if ret == nil do ret = Bool(true)
            boolean, ok2 := ret.(Bool)
            if !ok2 {
                error(
                    "Runtime Error iter function within `while` `%v` may only return Bool. Got %v.\nTrue = continue iterating, False = break iteration",
                    func, ret
                )
                return nil, false
            }

            if boolean == Bool(false) {
                broken = true
                break
            }
        }

        return Bool(broken), true
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

        case Function_Ref, ^Group:
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

    defs["global.group"] = proc(args: []Primitive, _: Function_Context) -> (Primitive, bool) {
        group := new(Group, base_allocator)
        group^ = make(Group, base_allocator)
        append(group, ..args)

        gc_manage_group(&gc, group)

        return group, true
    }

    defs["global.get"] = proc(args: []Primitive, _: Function_Context) -> (Primitive, bool) {
        if len(args) != 2 {
            error("Runtime Error function `get` expects two arguments.\nUsage: get group index")
            return nil, false
        }

        // TODO: Extend this to strings?
        group, ok := args[0].(^Group)
        if !ok {
            error("Runtime Error function `get` expects a Group as its first argument, got %v", args[0])
            return nil, false
        }

        index, ok2 := args[1].(Number)
        if !ok2 {
            error("Runtime Error function `get` expects a Number as its second argument, got %v", args[1])
            return nil, false
        }

        ind := int(index)

        if ind < 0 {
            ind = len(group) + ind
        }

        if ind >= len(group) || ind < 0 {
            error("Runtime Error group has %v elements, indexed at %v", len(group), index)
            return nil, false
        }

        return group[ind], true
    }

    defs["global.len"] = proc(args: []Primitive, _: Function_Context) -> (Primitive, bool) {
        if len(args) != 1 {
            error("Runtime Error function `len` only accepts one argument, got %v", args)
            return nil, false
        }

        #partial switch arg in args[0] {
        case String:
            return Number(len(arg)), true

        case ^Group:
            return Number(len(arg)), true

        case:
            error("Runtime Error function `len` only accepts String or Group, got %v", arg)
            return nil, false
        }
    }

    defs["global.append"] = proc(args: []Primitive, _: Function_Context) -> (Primitive, bool) {
        if len(args) < 2 {
            error("Runtime Error function `append` expects two arguments\nUsage: append group item ...")
            return nil, false
        }

        group, ok := args[0].(^Group)
        if !ok {
            error("Runtime Error function `append` expects the first argument to be a Group, got %v", args[0])
            return nil, false
        }

        append(group, ..args[1:])
        return group, true
    }

    defs["global.combine"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) < 2 {
            error("Runtime Error function `combine` expects two arguments\nUsage: combine group group ...")
            return nil, false
        }

        all_args_are(args, ^Group, "combine") or_return

        group := new(Group, base_allocator)
        group^ = make(Group, base_allocator)
        gc_manage_group(&gc, group)

        for g in args {
            other_group := g.(^Group)
            for elem in other_group {
                append(group, elem)
            }
        }

        return group, true
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
    
    case Return_Func:
        error("Runtime Error cannot use `return` func as lambda.")
        return nil, false
    }

    panic("Impossible")
}
