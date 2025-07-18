module lucy::errors;

import std::io;
import std::os;

import lucy::token;
import lucy::node;

const ERROR_PREVIOUS = "Previous definition was here";

fn void print(String file_path, Token token, String message) @noreturn
{
    String path = file_path.to_absolute_path(mem).str_view()!!;
    io::printn(Ansi.BRIGHT_RED);
    io::eprintfn("Something went wrong: %s", message);

    int line_nr = token.line;
    int padding = 0;

    while (line_nr != 0)
    {
        line_nr /= 10;
        padding++;
    }
    
    usz first_line = token.line - (token.ctx.len - 1);
    for (usz i = 0; i < token.ctx.len; i++)
    {
        io::printf("%-*d: %s", padding, first_line + i, token.ctx[i]);
    }

    if (token.ctx.len > 0)
    {
        usz last_line_idx = token.ctx.len - 1;

        padding += 2 + token.range.start;

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

fn void print_range(String file_path, int line, Range range, String[] ctx, String message) @noreturn
{
    String path = file_path.to_absolute_path(mem).str_view()!!;
    io::printn(Ansi.BRIGHT_RED);
    io::eprintfn("Something went wrong: %s", message);

    int line_nr = line;
    int padding = 0;

    while (line_nr != 0)
    {
        line_nr /= 10;
        padding++;
    }
    
    usz first_line = line - (ctx.len - 1);
    for (usz i = 0; i < ctx.len; i++)
    {
        io::printf("%-*d: %s", padding, first_line + i, ctx[i]);
    }

    if (ctx.len > 0)
    {
        usz last_line_idx = ctx.len - 1;

        padding += 2 + range.start;

        for (int i = 0; i < padding; i++)
        {
            io::print(" ");
        }

        for (int i = 0; i < range.end - range.start; i++)
        {
            io::print("^");
        }
        io::printn();
        io::printfn("Error in file (%s) %d:%d", path, line, range.start);
    }
    io::print(Ansi.RESET);
    os::exit(1); // TODO: remove
}

fn void print_node(String file_path, ASTNode node, String message)
{
    String path = file_path.to_absolute_path(mem).str_view()!!;
    io::printn(Ansi.BRIGHT_RED);
    io::eprintfn("Something went wrong: %s", message);

    int line_nr = node.line;
    int padding = 0;

    while (line_nr != 0)
    {
        line_nr /= 10;
        padding++;
    }

    usz first_line = node.line - (node.ctx.len - 1);
    for (usz i = 0; i < node.ctx.len; i++)
    {
        io::printf("%2d: %s", first_line + i, node.ctx[i]);
    }

    if (node.ctx.len > 0)
    {
        usz    last_line_idx = node.ctx.len - 1;
        String error_line    = node.ctx[last_line_idx];

        padding += 2 + node.range.start;

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
