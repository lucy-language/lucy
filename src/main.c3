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
import llvm;

fn int main(String[] args)
{
    Option[] options =
    {
        {
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
        },
        {
            .short_name  = 'l',
            .long_name   = "link",
            .description = "Links the set library",
            .has_arg     = true
        }
    };

    ArgParser arg_parser = { args, options };
    arg_parser.parse();

    if (arg_parser.has_arg("version"))
    {
        io::printfn("%-*s%s", 30, "Compiler Version:", VERSION);
        io::printfn("%-*s%s", 30, "Backends:", BACKENDS);
        for (int i = 0; i < 30 + VERSION.len; i++)
        {
            io::print("─");
        }
        io::printn();
        io::printfn("%-*s%s", 30, "LLVM Default Target:", (ZString)llvm::get_default_target_triple());
        return 0;
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
            return 0;
        }

        Parser parser = parser::new(lexer, path);
        ASTNode ast   = parser.parse();
    
        if (arg_parser.has_arg("tree"))
        {
            io::printn(json::to_json(ast, mem)!!);
        }

        if (arg_parser.has_arg("ast"))
        {
            file::save("ast.json", json::to_json(ast, mem))!!;
        }

        if (arg_parser.has_arg("parser"))
        {
            return 0;
        }

        String[] links = {"lucy/stdlib/io.lc"}; // TODO: take from argparser

        TypeTable* type_table = malloc(TypeTable.sizeof);
        (*type_table).init();
        SemanticAnalyser semantic_analyser = semantic_analyser::new(path, ast, type_table);
        semantic_analyser.analyse(links);

        if (arg_parser.has_arg("analyser"))
        {
            return 0;
        }
    
        // Need to reinstantiate because json fucks it up somehow
        // TODO: fix
        parser = parser::new(lexer, path);
        Compiler compiler = compiler::new(path, parser.parse(), type_table);
        compiler.compile(links);

        linker::link(compiler.mod, compiler.module_name, compiler.linker_options);
    }

    return 0;
}
