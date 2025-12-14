package main

import "core:unicode"
import "core:log"
import "core:strconv"

Token_Type :: enum {
    Number,
    Bool,
    String,
    Identifier,
    Open_Paren,
    Close_Paren,
    Equals,
    Semicolon,
    EOF,
    Error,
}

Token :: struct {
    line_number: int,
    span: [2]int,
    type: Token_Type,
    data: string,
    reason: string, // used for errors only
}

Lexer :: struct {
    data: []u8,
    index: int,
    line: int,
    column: int,
}

peek_next :: proc(lexer: ^Lexer) -> Token {
    index := lexer.index
    line := lexer.line
    column := lexer.column

    token := get_next(lexer)

    lexer.index = index
    lexer.line = line
    lexer.column = column
    return token
}

get_next :: proc(lexer: ^Lexer) -> Token {
    for {
        if lexer.index >= len(lexer.data) {
            return Token{-1, {-1, -1}, .EOF, "", ""}
        }

        start := lexer.column
        current := rune(lexer.data[lexer.index])

        if current == '\n' {
            lexer.index += 1
            lexer.line += 1
            lexer.column = 0
            continue
        }
        
        if unicode.is_white_space(current) {
            lexer.index += 1
            lexer.column += 1
            continue
        }

        switch {
            case match(lexer, "//"): skip_comment(lexer)
            case match(lexer, "{"): return make_token(lexer, start, .Open_Paren)
            case match(lexer, "}"): return make_token(lexer, start, .Close_Paren)
            case match(lexer, ";"): return make_token(lexer, start, .Semicolon)
            case match(lexer, "="): return make_token(lexer, start, .Equals)
            case match(lexer, "true"): return make_token(lexer, start, .Bool)
            case match(lexer, "false"): return make_token(lexer, start, .Bool)
            case match(lexer, "\""): return match_string(lexer)
        }

        // Attempt to parse an f64
        // This kinda feels like cheating lol
        remaining_str := transmute(string)lexer.data[lexer.index:]
        if _, num_len, ok := strconv.parse_f64_prefix(remaining_str); ok {
            lexer.index += num_len
            lexer.column += num_len
            return make_token(lexer, start, .Number)
        }

        // Attempt to lex an identifier
        if token, ok := match_identifier(lexer); ok {
            return token
        }
    }
}

// helpers

match_identifier :: proc(lexer: ^Lexer) -> (Token, bool) {
    start := lexer.column
    ok := false

    for {
        if lexer.index >= len(lexer.data) {
            return make_token(lexer, start, .Identifier), ok
        }

        current := rune(lexer.data[lexer.index])
        if unicode.is_space(current) {
            return make_token(lexer, start, .Identifier), ok
        }

        switch current {
            case ';', '{', '}', '=', '"': return make_token(lexer, start, .Identifier), ok
        }

        lexer.index += 1
        lexer.column += 1
        ok = true
    }
}

skip_comment :: proc(lexer: ^Lexer) {
    for {
        if lexer.index >= len(lexer.data) {
            return
        }

        current := rune(lexer.data[lexer.index])
        if current == '\n' {
            return
        }

        lexer.index += 1
        lexer.column += 1
    }
}

match_string :: proc(lexer: ^Lexer) -> Token {
    // starting " has already been consumed
    start_column := lexer.column
    start_index := lexer.index
    for {
        if lexer.index >= len(lexer.data) {
            return make_token(lexer, start_column, .Error, "Unterminated string")
        }

        current := rune(lexer.data[lexer.index])

        if current == '\n' {
            return make_token(lexer, start_column, .Error, "Unterminated string")
        }

        // TODO: special characters: \n, \t, \", etc
        if current == '"' {
            token := make_token(lexer, start_column, .String)
            // Consume the closing "
            lexer.index += 1
            lexer.column += 1
            return token
        }

        lexer.index += 1
        lexer.column += 1
    }
}

// Returns true if the next tokens match the target string
// When a match is found the lexer is progressed
// When a match is not found the lexer is not progressed
match :: proc(lexer: ^Lexer, target: string) -> bool {
    index := lexer.index
    target := transmute([]u8) target

    for c in target {
        if index >= len(lexer.data) {
            return false
        }

        if lexer.data[index] != c {
            return false
        }
        index += 1
    }

    size := index - lexer.index
    lexer.column += size
    lexer.index = index
    return true
}

make_token :: proc(lexer: ^Lexer, start_column: int, type: Token_Type, reason := "") -> Token {
    start_index := lexer.index - (lexer.column - start_column)
    data_slice := lexer.data[start_index : lexer.index]
    return Token{lexer.line, {start_column, lexer.column}, type, transmute(string)data_slice, reason}
}
