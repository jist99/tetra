package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "vendor:raylib"

register_builtins :: proc(output: ^map[string]Function_Entry) {
    defs := make(map[string]Function)
    defer delete(defs)

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

    defs["global.not"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 1 {
            error("Runtime Error function `not` only accepts one argument\nUsage: not bool")
            return nil, false
        }

        arg := as_type(args, 0, Bool, "not") or_return
        return Bool(!bool(arg)), true
    }

    defs["global.and"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 2 {
            error("Runtime Error function `and` only accepts two args\nUsage: and bool bool")
            return nil, false
        }

        a := as_type(args, 0, Bool, "and") or_return
        b := as_type(args, 1, Bool, "and") or_return
        return Bool(bool(a) && bool(b)), true
    }

    defs["global.or"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 2 {
            error("Runtime Error function `or` only accepts two args\nUsage: or bool bool")
            return nil, false
        }

        a := as_type(args, 0, Bool, "or") or_return
        b := as_type(args, 1, Bool, "or") or_return
        return Bool(bool(a) || bool(b)), true
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
        if len(args) < 2 || len(args) > 3 {
            error("Runtime Error function `if` only accepts two-three arguments.\nUsage: if cond then [else]")
        }
        
        cond := as_type_or_func(args, 0, Bool, super, "if") or_return
        cond_satisfied := bool(cond)

        _ = as_type(args, 1, Function_Ref, "if") or_return
        if len(args) == 3 {
            _ = as_type(args, 1, Function_Ref, "if") or_return
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

    defs["global.set"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        // set group idx value
        if len(args) != 3 {
            error("Runtime Error function `set` requires 3 arguments\nUsage: set group idx value")
            return nil, false
        }

        group := as_type(args, 0, ^Group, "set") or_return
        idx := as_type(args, 1, Number, "set") or_return
        value := args[2]

        group[int(idx)] = value
        return nil, true
    }

    // Raylib functions!
    defs["global.init_window"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 3 {
            error("Runtime Error init_window requires 3 args\nUsage: init_window width height name")
            return nil, false
        }

        width := as_type(args, 0, Number, "init_window") or_return
        height := as_type(args, 1, Number, "init_window") or_return
        name := as_type(args, 2, String, "init_window") or_return

        c_name := strings.clone_to_cstring(string(name), context.temp_allocator)
        raylib.InitWindow(i32(width), i32(height), c_name)
        return nil, true
    }

    defs["global.window_should_close"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        should_close := raylib.WindowShouldClose()
        return Bool(should_close), true
    }

    defs["global.begin_drawing"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        raylib.BeginDrawing()
        return nil, true
    }

    defs["global.end_drawing"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        raylib.EndDrawing()
        return nil, true
    }

    defs["global.draw_text"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 5 {
            error("Runtime Error draw_text requires 5 arguments")
            return nil, false
        }

        text := as_type(args, 0, String, "draw_text") or_return
        pos_x := as_type(args, 1, Number, "draw_text") or_return
        pos_y := as_type(args, 2, Number, "draw_text") or_return
        font_size := as_type(args, 3, Number, "draw_text") or_return
        ray_colour := as_colour(args, 4, "draw_text") or_return

        c_text := strings.clone_to_cstring(string(text), context.temp_allocator)
        raylib.DrawText(c_text, i32(pos_x), i32(pos_y), i32(font_size), ray_colour)
        return nil, true
    }

    defs["global.is_key_down"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 1 {
            error("Runtime Error `is_key_down` only accepts one argument, the keycode.")
            return nil, false
        }

        keycode := as_type(args, 0, Number, "is_key_down") or_return
        return Bool(raylib.IsKeyDown(raylib.KeyboardKey(keycode))), true
    }

    defs["global.is_key_pressed"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 1 {
            error("Runtime Error `is_key_pressed` only accepts one argument, the keycode.")
            return nil, false
        }

        keycode := as_type(args, 0, Number, "is_key_pressed") or_return
        return Bool(raylib.IsKeyPressed(raylib.KeyboardKey(keycode))), true
    }

    defs["global.draw_rectangle_v"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 3 {
            error("Runtime Error draw_rectangle_v expects 3 args\nUsage: draw_rectangle_v position size colour")
            return nil, false
        }

        position := as_vector2(args, 0, "draw_rectangle_v") or_return
        size := as_vector2(args, 1, "draw_rectangle_v") or_return
        colour := as_colour(args, 2, "draw_rectangle_v") or_return

        raylib.DrawRectangleV(position, size, colour)
        return nil, true
    }

    defs["global.clear_background"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 1 {
            error("Runtime Error clear_background expects 1 arg\nUsage: clear_background colour")
            return nil, false
        }

        colour := as_colour(args, 0, "clear_background") or_return
        raylib.ClearBackground(colour)
        return nil, true
    }

    defs["global.get_frame_time"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        ft := raylib.GetFrameTime()
        return Number(ft), true
    }

    defs["global.get_random_value"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 2 {
            error("Runtime Error get_random_value requires 2 args - min and max.")
            return nil, false
        }

        min := as_type(args, 0, Number, "get_random_value") or_return
        max := as_type(args, 1, Number, "get_random_value") or_return

        value := raylib.GetRandomValue(i32(min), i32(max))
        return Number(value), true
    }

    defs["global.check_collision_recs"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 2 {
            error("Runtime Error check_collision_recs requires 2 args. Rec 1 and Rec 2")
            return nil, false
        }

        rec1 := as_type(args, 0, ^Group, "check_collision_recs") or_return
        rec2 := as_type(args, 1, ^Group, "check_collision_recs") or_return

        // I'm being very lazy and not doing error checking properly
        ray_rect_1: raylib.Rectangle
        ray_rect_1.x = f32(rec1[0].(^Group)[0].(Number))
        ray_rect_1.y = f32(rec1[0].(^Group)[1].(Number))
        ray_rect_1.width = f32(rec1[1].(^Group)[0].(Number))
        ray_rect_1.height = f32(rec1[1].(^Group)[1].(Number))

        ray_rect_2: raylib.Rectangle
        ray_rect_2.x = f32(rec2[0].(^Group)[0].(Number))
        ray_rect_2.y = f32(rec2[0].(^Group)[1].(Number))
        ray_rect_2.width = f32(rec2[1].(^Group)[0].(Number))
        ray_rect_2.height = f32(rec2[1].(^Group)[1].(Number))

        collision := raylib.CheckCollisionRecs(ray_rect_1, ray_rect_2)
        return Bool(collision), true
    }

    defs["global.draw_circle_sector"] = proc(args: []Primitive, _: Function_Context) -> (out: Primitive, ok: bool) {
        if len(args) != 6 {
            error("Runtime Error draw_circle_sector expects 6 args\nUsage: draw_circle centre radius startAngle endAngle segments colour")
            return nil, false
        }

        centre := as_vector2(args, 0, "draw_circle_sector") or_return
        radius := as_type(args, 1, Number, "draw_circle_sector") or_return
        start_angle := as_type(args, 2, Number, "draw_circle_sector") or_return
        end_angle := as_type(args, 3, Number, "draw_circle_sector") or_return
        segments := as_type(args, 4, Number, "draw_circle_sector") or_return
        colour := as_colour(args, 5, "draw_circle_sector") or_return

        raylib.DrawCircleSector(centre, f32(radius), f32(start_angle), f32(end_angle), i32(segments), colour)
        return nil, true
    }

    for key, value in defs {
        output[key] = Function_Entry{value, true}
    }
}

// Helpers
as_vector2 :: proc(args: []Primitive, idx: int, source: string) -> (out: raylib.Vector2, ok: bool) {
    group := as_type(args, idx, ^Group, source) or_return

    if len(group) != 2 {
        error("Runtime Error Vector2 must have 2 values xy, got %v", group)
        ok = false
        return
    }

    vector: raylib.Vector2
    for entry, i in group {
        num, ok := entry.(Number)
        if !ok {
            error("Runtime Error Vector2 may only contain Numbers, got %v", entry)
            ok = false
            return
        }
        vector[i] = f32(num)
    }
    return vector, true
}

as_colour :: proc(args: []Primitive, idx: int, source: string) -> (out: raylib.Color, ok: bool) {
    colour := as_type(args, idx, ^Group, source) or_return

    if len(colour) != 4 {
        error("Runtime Error Colour must have 4 values RGBA, got %v", colour)
        ok = false
        return
    }
    ray_colour: raylib.Color
    for entry, i in colour {
        num, ok := entry.(Number)
        if !ok {
            error("Runtime Error Colour may only contain Numbers, got %v", entry)
            ok = false
            return
        }
        ray_colour[i] = u8(num)
    }
    return ray_colour, true
}

@(private="file")
as_type :: proc(args: []Primitive, idx: int, $T: typeid, source: string) -> (out: T, ok: bool) {
    out, ok = args[idx].(T)
    if !ok {
        error("Runtime Error %v arg %v must be %v", source, idx, typeid_of(T))
    }
    return
}

@(private="file")
as_type_or_func :: proc(args: []Primitive, idx: int, $T: typeid, super: Function_Context, source: string) -> (out: T, ok: bool) {
    if func, is_func := args[idx].(Function_Ref); is_func {
        value, valid := execute_func(func, super, {})
        if !valid do return

        out, ok = value.(T)
        if !ok {
            error("Runtime Error anonymous function for %v returned %v expecting type %v", source, out, typeid_of(T))
        }
        return
    }

    return as_type(args, idx, T, source)
}

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

    switch raw_fn in func.func {
    case proc([]Primitive, Function_Context) -> (Primitive, bool):
        return raw_fn(args, super)

    case [dynamic]Statement:
        return execute(raw_fn[:], super.definitions, super.dcm, args, func.is_global, string(ref))
    
    case Return_Func:
        error("Runtime Error cannot use `return` func as lambda.")
        return nil, false
    }

    panic("Impossible")
}
