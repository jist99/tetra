package main

import "core:mem"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:log"

// AST
Bool :: distinct bool
Identifier :: distinct string
Number :: distinct f64
String :: distinct string

Atom :: union {
    Bool,
    Identifier,
    Number,
    String,
}

Call :: struct {
    name: Identifier,
    function: Identifier,
    args: [dynamic]Atom,
}

Definition :: struct {
    name: Identifier,
    statements: [dynamic]Statement,
}

Statement :: union {
    Call,
    Definition,
}


// Parsing
Parser :: struct {
    using lexer: ^Lexer,
    errors: [dynamic]string,
    anonymous_functions: [dynamic]Definition,
}

parse :: proc(parser: ^Parser, alloc: mem.Allocator) -> ([dynamic]Statement, bool) {
    context.allocator = alloc

    parser.anonymous_functions = make([dynamic]Definition)

    statements := parse_statements(parser)

    for anon in parser.anonymous_functions {
        append(&statements, anon)
    }

    ok := len(parser.errors) == 0

    return statements, ok
}

parse_statements :: proc(parser: ^Parser) -> [dynamic]Statement{
    statements := make([dynamic]Statement)

    for {
        next := peek_next(parser)
        if next.type == .EOF || next.type == .Close_Paren {
            break
        }

        assignment := edr(parser, .Identifier) or_continue
        name := Identifier(assignment.data)
        edr(parser, .Equals) or_continue

        if peek_next(parser).type == .Open_Paren {
            // function definition
            definition, ok := parse_function_definition(parser, name)
            if !ok {
                recover(parser)
                continue
            }
            append(&statements, definition)
        } else {
            // function call
            call, ok := parse_function_call(parser, name)
            if !ok {
                recover(parser)
                continue
            }
            append(&statements, call)
        }
    }

    return statements
}

parse_function_call :: proc(parser: ^Parser, name: Identifier) -> (call: Call, ok: bool) {
    function := ed(parser, .Identifier) or_return
    args := make([dynamic]Atom)

    for {
        peek := peek_next(parser).type
        if peek == .EOF || peek == .Semicolon {
            break
        }

        if peek == .Open_Paren {
            builder := strings.builder_make()
            anon_name := fmt.sbprintf(&builder, "anon_%v", len(parser.anonymous_functions))
            anon := parse_function_definition(parser, Identifier(anon_name), true) or_return
            append(&parser.anonymous_functions, anon)
            append(&args, Identifier(anon_name))
            continue
        }

        current := get_next(parser)
        #partial switch current.type {
        case .Number:
            number := strconv.parse_f64(current.data) or_else panic("Number token isnt parsable")
            append(&args, Number(number))

        case .Bool:
            b := strconv.parse_bool(current.data) or_else panic("Bool token isnt parsable")
            append(&args, Bool(b))

        case .String:
            append(&args, String(current.data))

        case .Identifier:
            append(&args, Identifier(current.data))

        case .Error:
            ok = false
            display_error(parser, current)
            return

        case:
            current.type = .Error
            current.reason = "Unexpected token in function call"
            display_error(parser, current)
            ok = false
            return
        }
    }

    ed(parser, .Semicolon) or_return

    call = Call{name, Identifier(function.data), args}
    ok = true
    return
}

parse_function_definition :: proc(parser: ^Parser, name: Identifier, is_anon := false) -> (def: Definition, ok: bool) {
    _ = expect(parser, .Open_Paren) or_else panic("Impossible: No opening { in function")
    statements := parse_statements(parser)
    ed(parser, .Close_Paren) or_return
    if !is_anon {
        ed(parser, .Semicolon) or_return
    }

    def = Definition{name, statements}
    return def, true
}

// helpers
expect :: proc(parser: ^Parser, type: Token_Type) -> (token: Token, ok: bool) {
    token = peek_next(parser)
    
    if token.type == .Error {
        get_next(parser) // consume the error
        ok = false
        return
    }

    if token.type != type {
        builder := strings.builder_make()
        msg := fmt.sbprintf(
            &builder,
            "Expected token %v, found %v, `%v` instead",
            type, token.type, token.data
        )

        token = Token{token.line_number, token.span, .Error, token.data, msg}
        ok = false
        return
    }

    get_next(parser) // success, consume the token
    ok = true
    return
}

display_error :: proc(parser: ^Parser, token: Token) {
    ensure(token.type == .Error)

    builder := strings.builder_make()
    msg := fmt.sbprintf(
        &builder,
        "Parser Error at (%v, %v:%v): %v",
        token.line_number, token.span.x, token.span.y, token.reason
    )

    append(&parser.errors, msg)
}

// recover from a parsing error. We will try to get to the next statement
// by searching for a closing ;
recover :: proc(parser: ^Parser) {
    for {
        current := get_next(parser)

        if current.type == .Semicolon do return
        if current.type == .Identifier && peek_next(parser).type == .Equals do return
        if current.type == .EOF do panic("Unable to recover from error")
    }
}

// Expect Display
// Combines the two functions into one convenience function
ed :: proc(parser: ^Parser, type: Token_Type) -> (token: Token, ok: bool) {
    token, ok = expect(parser, type)
    if !ok {
        display_error(parser, token)
    }
    return
}

// Expect Display Recover
// Combines the three functions into one convenience function
edr :: proc(parser: ^Parser, type: Token_Type) -> (token: Token, ok: bool) {
    token, ok = ed(parser, type)
    if !ok {
        recover(parser)
    }
    return
}
