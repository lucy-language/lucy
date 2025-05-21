module lucy::errors;

import std::io;
import std::os;

import lucy::token;
import lucy::node;

import color_util;

fn void print(String file_path, Token token, String message)
{
    io::printn(color_util::COLOR_BRIGHT_RED);
    io::eprintfn("Something went wrong: %s", message);

    usz first_line = token.line - (token.context_lines.len() - 1);
    for (usz i = 0; i < token.context_lines.len(); i++)
    {
        io::printf("%2d: %s", first_line + i, token.context_lines.get(i));
    }

    if (token.context_lines.len() > 0)
    {
        usz last_line_idx = token.context_lines.len() - 1;
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
        io::printfn("Error in file (%s) %d:%d", file_path, token.line, token.range.start);
    }
    io::printn(color_util::COLOR_RESET);
    os::exit(1); // TODO: remove
}

fn void print_node(String file_path, ASTNode node, String message)
{
    io::printn(color_util::COLOR_BRIGHT_RED);
    io::eprintfn("Something went wrong: %s", message);

    usz first_line = node.line - (node.context_lines.len() - 1);
    for (usz i = 0; i < node.context_lines.len(); i++)
    {
        io::printf("%2d: %s", first_line + i, node.context_lines.get(i));
    }

    if (node.context_lines.len() > 0)
    {
        usz last_line_idx = node.context_lines.len() - 1;
        String error_line = node.context_lines.get(last_line_idx);

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
        io::printfn("Error in file (%s) %d:%d", file_path, node.line, node.range.start);
    }
    io::printn(color_util::COLOR_RESET);
}