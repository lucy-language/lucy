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
            .description = "Stops after the lexing stage"
        },
        {
            .short_name  = 'p',
            .long_name   = "parser",
            .description = "Stops after the parsing stage"
        },
        {

            .long_name   = "compile",
            .description = "The file to compile",
            .value       = "FILE",
            .has_arg     = true,
            .subcommand  = true
        },
        {
            .short_name  = 't',
            .long_name   = "tree",
            .description = "Prints the AST in JSON format to stdout"
        },
        {
            .short_name  = 'T',
            .long_name   = "ast",
            .description = "Writes the AST in JSON to a file"
        },
        {
            .short_name  = 'a',
            .long_name   = "analyser",
            .description = "Stops after the analysing stage"
        },
        {
            .short_name  = 'v',
            .long_name   = "version",
            .description = "prints version info to stdout"
        }
    };

    ArgParser arg_parser = { args, options };
    arg_parser.parse();

    if (arg_parser.has_arg("version"))
    {
        io::printfn("Compiler Version:     %s", VERSION);
        io::printfn("Backends:             %s", BACKENDS);
        os::exit(0);
    }

    if (arg_parser.has_arg("compile"))
    {
        String path    = arg_parser.get_arg("compile");
        String content = (String)file::load(mem, path)!!;

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
            io::printn(json::to_json(ast, mem, true)!!);
        }

        if (arg_parser.has_arg("ast"))
        {
            file::save("ast.json", json::to_json(ast, mem, true))!!;
        }

        if (arg_parser.has_arg("parser"))
        {
            os::exit(0);
        }

        SemanticAnalyser semantic_analyser = semantic_analyser::new(path, ast);
        semantic_analyser.analyse();

        if (arg_parser.has_arg("analyser"))
        {
            os::exit(0);
        }
    
        // Need to reinstantiate because json fucks it up somehow
        // TODO: fix
        parser = parser::new(lexer, path);
        Compiler compiler = compiler::new(path, parser.parse());
        compiler.compile();
    }

    return 0;
}
