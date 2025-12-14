package test

import main "../src"
import "core:testing"
import "core:log"

@test
test_basic_tokens :: proc(t: ^testing.T) {
    lexer := make_lexer("true false   {   }\n;=")

    testing.expect(t, main.get_next(&lexer).type == .Bool)
    testing.expect(t, main.get_next(&lexer).type == .Bool)
    testing.expect(t, main.get_next(&lexer).type == .Open_Paren)
    testing.expect(t, main.get_next(&lexer).type == .Close_Paren)
    testing.expect(t, main.get_next(&lexer).type == .Semicolon)
    testing.expect(t, main.get_next(&lexer).type == .Equals)
}

@test
test_token_data :: proc(t: ^testing.T) {
    lexer := make_lexer("true\nfalse {}\n// skip comments\n;")

    token := main.get_next(&lexer)
    testing.expect(t, token == main.Token{0, {0,4}, .Bool, "true", ""})

    token = main.get_next(&lexer)
    testing.expect(t, token == main.Token{1, {0,5}, .Bool, "false", ""})

    token = main.get_next(&lexer)
    testing.expect(t, token == main.Token{1, {6,7}, .Open_Paren, "{", ""})

    token = main.get_next(&lexer)
    testing.expect(t, token == main.Token{1, {7,8}, .Close_Paren, "}", ""})

    token = main.get_next(&lexer)
    testing.expect(t, token == main.Token{3, {0,1}, .Semicolon, ";", ""})
}

@test
test_string :: proc(t: ^testing.T) {
    lexer := make_lexer(`  "hello"  "there
    "woo" "試験" "bad`)

    token := main.get_next(&lexer)
    testing.expect(t, token.data == "hello")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Error)
    testing.expect(t, token.reason == "Unterminated string")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .String)
    testing.expect(t, token.data == "woo")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .String)
    testing.expect(t, token.data == "試験")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Error)
    testing.expect(t, token.reason == "Unterminated string")
}

@test
test_number :: proc(t: ^testing.T) {
    lexer := make_lexer("123 1.23 4e10 -5 -5.1")

    token := main.get_next(&lexer)
    testing.expect(t, token.type == .Number)
    testing.expect(t, token.data == "123")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Number)
    testing.expect(t, token.data == "1.23")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Number)
    testing.expect(t, token.data == "4e10")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Number)
    testing.expect(t, token.data == "-5")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Number)
    testing.expect(t, token.data == "-5.1")
}

@test
test_identifier :: proc(t: ^testing.T) {
    lexer := make_lexer("my_id another_id; more + - * / ended_by\nended_by_eof")

    token := main.get_next(&lexer)
    testing.expect(t, token.type == .Identifier)
    testing.expect(t, token.data == "my_id")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Identifier)
    testing.expect(t, token.data == "another_id")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Semicolon)

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Identifier)
    testing.expect(t, token.data == "more")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Identifier)
    testing.expect(t, token.data == "+")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Identifier)
    testing.expect(t, token.data == "-")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Identifier)
    testing.expect(t, token.data == "*")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Identifier)
    testing.expect(t, token.data == "/")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Identifier)
    testing.expect(t, token.data == "ended_by")

    token = main.get_next(&lexer)
    testing.expect(t, token.type == .Identifier)
    testing.expect(t, token.data == "ended_by_eof")
}

// helpers
make_lexer :: proc(text: string) -> main.Lexer {
    return main.Lexer{data=transmute([]u8)text}
}
