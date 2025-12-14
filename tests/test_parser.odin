package test

import main "../src"
import la "../src/lazytools/allocators"
import "core:testing"
import "core:log"
import "core:fmt"

@test
test_calls :: proc(t: ^testing.T) {
    a: la.Auto_Free_Allocator
    context.allocator = la.auto_free_allocator(&a)

    lexer := make_lexer(`a = + 1 2;`)
    parser := main.Parser{&lexer, make([dynamic]string)}

    ast, ok := main.parse(&parser, context.allocator)
    
    testing.expect(t, len(ast) == 1)
    testing.expect(t, ast[0].(main.Call).name == main.Identifier("a"))
    testing.expect(t, ast[0].(main.Call).function == main.Identifier("+"))
    testing.expect(t, ast[0].(main.Call).args[0] == main.Number(1))
    testing.expect(t, ast[0].(main.Call).args[1] == main.Number(2))

    free_all()
}

@test
test_func :: proc(t: ^testing.T) {
    a: la.Auto_Free_Allocator
    context.allocator = la.auto_free_allocator(&a)

    lexer := make_lexer(
        `foo = {
            a = - 1 2;
        };`
    )
    parser := main.Parser{&lexer, make([dynamic]string)}

    ast, ok := main.parse(&parser, context.allocator)

    testing.expect(t, ast[0].(main.Definition).name == "foo")
    testing.expect(t, ast[0].(main.Definition).statements[0].(main.Call).name == "a")

    free_all()
}

main :: proc(){
    test_calls(nil)
}
