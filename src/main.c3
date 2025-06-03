module lucy;

import std;

import lucy::semantic_analyser;
import lucy::compiler;
import lucy::parser;
import lucy::lexer;
import lucy::node;

import argparser;
import color_util;
import json;

fn int main(String[] args)
{
    Option[] options =
    {
        {
            .short_name  = 'l',
            .long_name   = "lexer",
            .description = "Stops after the lexing stage",
            .has_arg     = false,
            .required    = false
        },
        {
            .short_name  = 'p',
            .long_name   = "parser",
            .description = "Stops after the parsing stage",
            .has_arg     = false,
            .required    = false
        },
        {

            .short_name  = 'f',
            .long_name   = "file",
            .description = "The file to compile",
            .has_arg     = true,
            .required    = true
        },
        {
            .short_name  = 't',
            .long_name   = "tree",
            .description = "Prints the AST in JSON format to stdout",
            .has_arg     = false,
            .required    = false
        },
        {
            .short_name  = 'T',
            .long_name   = "ast",
            .description = "Writes the AST in JSON to a file",
            .has_arg     = false,
            .required    = false
        }
    };

    ArgParser arg_parser = { args, options };
    arg_parser.parse();

    String path    = arg_parser.get_arg("file");
    String content = read_file(path);

    lucy::lexer::Lexer lexer = lexer::new(content);

    if (arg_parser.has_arg("lexer"))
    {
        foreach(token : lexer.tokenize())
        {
            io::printn(token.type);
        }
        os::exit(0);
    }

    Parser parser = parser::new(lexer, path);
    ASTNode ast   = parser.parse();
    
    if (arg_parser.has_arg("tree"))
    {
        io::printn(json::to_json(ast, mem)!!);
    }

    if (arg_parser.has_arg("ast"))
    {
        file::save("ast.json", json::to_json(ast, mem)!!)!!;
    }

    if (arg_parser.has_arg("parser"))
    {
        os::exit(0);
    }

//    io::printn(json::to_json(ast, mem)!!);

    SemanticAnalyser semantic_analyser = semantic_analyser::new(path, ast);
    semantic_analyser.analyse();

    Compiler compiler = compiler::new(path, ast);
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
