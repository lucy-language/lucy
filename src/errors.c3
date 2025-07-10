module lucy::errors;

import std::io;
import std::os;

import lucy::token;
import lucy::node;

fn void print(String file_path, Token token, String message) @noreturn
{
    String path = file_path.to_absolute_path(mem).str_view()!!;
    io::printn(Ansi.BRIGHT_RED);
    io::eprintfn("Something went wrong: %s", message);

    usz first_line = token.line - (token.ctx.len - 1);
    for (usz i = 0; i < token.ctx.len; i++)
    {
        io::printf("%2d: %s", first_line + i, token.ctx[i]);
    }

    if (token.ctx.len > 0)
    {
        usz last_line_idx = token.ctx.len - 1;
        int padding = 4 + token.range.start;

        for (int i = 0; i < padding; i++)
        {
            io::print(" ");
        }

        for (int i = 0; i < token.range.end - token.range.start; i++)
        {
            io::print("^");
        }
        io::printn();
        io::printfn("Error in file (%s) %d:%d", path, token.line, token.range.start);
    }
    io::print(Ansi.RESET);
    os::exit(1); // TODO: remove
}

fn void print_node(String file_path, ASTNode node, String message)
{
    String path = file_path.to_absolute_path(mem).str_view()!!;
    io::printn(Ansi.BRIGHT_RED);
    io::eprintfn("Something went wrong: %s", message);

    usz first_line = node.line - (node.ctx.len - 1);
    for (usz i = 0; i < node.ctx.len; i++)
    {
        io::printf("%2d: %s", first_line + i, node.ctx[i]);
    }

    if (node.ctx.len > 0)
    {
        usz last_line_idx = node.ctx.len - 1;
        String error_line = node.ctx[last_line_idx];

        int padding = 4 + node.range.start;

        for (int i = 0; i < padding; i++)
        {
            io::print(" ");
        }

        for (int i = 0; i < node.range.end - node.range.start; i++)
        {
            io::print("^");
        }
        io::printn();
        io::printfn("Error in file (%s) %d:%d", path, node.line, node.range.start);
    }
    io::print(Ansi.RESET);
}
