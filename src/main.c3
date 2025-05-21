module lucy;

import std::core::mem;
import std::io::file;
import std::io;
import std::os;

import lucy::semantic_analyser;
import lucy::compiler;
import lucy::parser;
import lucy::lexer;

import argparser;
import color_util;

fn int main(String[] args)
{
    Option[] options =
    {
        {
            .short_name  = 'f',
            .long_name   = "file",
            .description = "The file to compile",
            .has_arg     = true,
            .required    = true
        }
    };

    ArgParser arg_parser = { args, options };
    arg_parser.parse();

    String path    = arg_parser.get_arg("file");
    String content = read_file(path);
    Lexer  lexer   = lexer::new(content);
    Parser parser  = parser::new(lexer, path);

    SemanticAnalyser semantic_analyser = semantic_analyser::new(parser);
    semantic_analyser.analyse();

    Compiler compiler = compiler::new(parser);
    compiler.compile();

    return 0;
}

fn String read_file(String path)
{
    File? file     = file::open(path, "r");

    if (catch file)
    {
        io::eprintfn("%sFile `%s` not found%s", color_util::COLOR_BRIGHT_RED, path, color_util::COLOR_RESET);
        os::exit(1);
    }

    usz size      = file::get_size(path)!!;
    String buffer = (String)mem::new_array(char, size);

    file.read(buffer)!!;

    return buffer;
}