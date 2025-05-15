module lucy::parser;

import std::collections::list;
import std::core::string;
import std::core::mem;
import std::io::path;

import lucy::errors;
import lucy::token;
import lucy::lexer;
import lucy::node;

struct Parser
{
    TokenList tokens;
    int       pos;
    Token     current;
    String    file_path;
}

fn Parser new(Lexer lexer, String path)
{
    TokenList tokens = lexer.tokenize();
    int pos = 0;
    Path file_path = path.to_absolute_path(mem)!!;

    return
    {
        .tokens    = tokens,
        .pos       = pos,
        .current   = tokens[pos],
        .file_path = file_path.str_view()
    };
}

fn void Parser.consume(&self)
{
    self.pos++;
    if (self.pos < self.tokens.len())
    {
        self.current = self.tokens[self.pos];
    }
}

fn void Parser.try_consume(&self, TokenType type)
{
    if (self.current.type == type)
    {
        self.consume();
    } else
    {
        errors::print(self.file_path, self.current, string::tformat("%s expected, got %s", type.str, self.current.type.str));
    }
}

fn ASTNode Parser.parse(&self)
{
    ASTNodeList children;
    ASTNodeList linker_options = self.linker_options();

    String module_name = self.pkg();

    while (self.current.type == TokenType.KW_USE)
    {
        children.push(self.use());
    }

    while (self.current.type != TokenType.EOF)
    {
        switch (self.current.type)
        {
            case TokenType.KW_DEF: children.push(self.def());
            case TokenType.KW_EXT: children.push(self.ext());
            default: break;
        }
    }

    self.try_consume(TokenType.EOF);

    return
    {
        NodeType.FILE,
        {
            .file_node =
            {
                module_name,
                children
            }
        },
        {},
        0,
        {}
    };
}

fn ASTNodeList Parser.linker_options(&self)
{
    ASTNodeList linker_options;

    while (self.current.type == TokenType.PERCENT)
    {
        self.consume();

        DString value;
        value.append_chars(self.current.value);

        self.try_consume(TokenType.STRING);
        self.try_consume(TokenType.SEMICOLON);

        linker_options.push({
            NodeType.LINK,
            {
                .linker_option_node =
                {
                    value.str_view()
                }
            },
            {},
            0,
            {}
        });
    }

    return linker_options;
}

fn String Parser.pkg(&self)
{
    self.try_consume(TokenType.KW_PKG);

    String module_name = self.path();

    self.try_consume(TokenType.SEMICOLON);

    return module_name;
}

fn ASTNode Parser.use(&self)
{
    self.try_consume(TokenType.KW_USE);

    String path = self.path();

    self.try_consume(TokenType.SEMICOLON);

    return
    {
        NodeType.USE,
        {
            .use_node =
            {
                path
            }
        },
        {},
        0,
        {}
    };
}

fn String Parser.path(&self)
{
    DString path;

    path.append_chars(self.current.value);
    self.try_consume(TokenType.IDENTIFIER);

    while (self.current.type == TokenType.PERIOD)
    {
        path.append_char('.');
        self.consume();
        path.append_chars(self.current.value);
        self.try_consume(TokenType.IDENTIFIER);
    }

    return path.str_view();
}

fn ASTNode Parser.def(&self)
{
    self.consume();

    String type = self.current.value;
    self.try_consume(TokenType.IDENTIFIER);

    String name = self.def_name();
    ASTNodeList parameters = self.def_parameters();

    ASTNodeList children;

    self.try_consume(TokenType.LBRACE);

    if (self.current.type == TokenType.KW_RETURN)
    {
        self.try_consume(TokenType.KW_RETURN);
        ASTNode value = self.expr();
        self.try_consume(TokenType.SEMICOLON);

        ASTNodeList value_list;
        value_list.push(value);

        children.push(
        {
            NodeType.RETURN,
            {
                .return_node =
                {
                    value_list
                }
            },
            {},
            0,
            {}
        });
    }

    self.try_consume(TokenType.RBRACE);

    return
    {
        NodeType.DEF,
        {
            .def_node =
            {
                type,
                name,
                parameters,
                children
            }
        },
        {},
        0,
        {}
    };
}

fn String Parser.def_name(&self)
{
    DString name;

    name.append_chars(self.current.value);
    self.try_consume(TokenType.IDENTIFIER);

    if (self.current.type == TokenType.PERIOD)
    {
        name.append_char('.');
        self.consume();
        name.append_chars(self.current.value);
        self.try_consume(TokenType.IDENTIFIER);
    }

    return name.str_view();
}

fn ASTNodeList Parser.def_parameters(&self)
{
    ASTNodeList parameters;

    self.try_consume(TokenType.LPAREN);

    if (self.current.type != TokenType.RPAREN)
    {
        List{String} context_lines = self.current.context_lines;
        int line = self.current.line;
        int range_start = self.current.range.start;
        bool vararg;
        DString type;

        if (self.current.type == TokenType.KW_VAR)
        {
            self.consume();
            vararg = true;
        }

        type.append_chars(self.current.value);
        self.try_consume(TokenType.IDENTIFIER);

        if (self.current.type == TokenType.LBRACKET)
        {
            self.consume();
            self.try_consume(TokenType.RBRACKET);

            type.append_chars("[]");
        }

        int range_end = self.current.range.end;
        String name = self.current.value;
        self.try_consume(TokenType.IDENTIFIER);

        parameters.push(
            {
                NodeType.PARAMETER,
                {
                    .parameter_node =
                    {
                        vararg,
                        type.str_view(),
                        name
                    }
                },
                {
                    range_start,
                    range_end,
                    range_end - range_start
                },
                line,
                context_lines
            }
        );

        while (self.current.type == TokenType.COMMA)
        {
            self.consume();

            List{String} other_context_lines = self.current.context_lines;
            int other_line = self.current.line;
            int other_range_start = self.current.range.start;
            bool other_vararg;
            DString other_type;

            if (self.current.type == TokenType.KW_VAR)
            {
                self.consume();
                other_vararg = true;
            }

            other_type.append_chars(self.current.value);
            self.try_consume(TokenType.IDENTIFIER);

            if (self.current.type == TokenType.LBRACKET)
            {
                self.consume();
                self.try_consume(TokenType.RBRACKET);

                other_type.append_chars("[]");
            }

            int other_range_end = self.current.range.end;
            String other_name = self.current.value;
            self.try_consume(TokenType.IDENTIFIER);

            parameters.push(
                {
                    NodeType.PARAMETER,
                    {
                        .parameter_node =
                        {
                            other_vararg,
                            other_type.str_view(),
                            other_name
                        }
                    },
                    {
                        other_range_start,
                        other_range_end,
                        other_range_end - other_range_start
                    },
                    other_line,
                    other_context_lines
                }
            );
        }
    }

    self.try_consume(TokenType.RPAREN);

    return parameters;
}

fn ASTNode Parser.expr(&self)
{
    ASTNode node = self.term();
    ASTNodeList left;
    left.push(node);

    int line = node.line;
    List{String} context_lines = node.context_lines;
    Range range =
    {
        .start = node.range.start
    };

    while (self.current.type == TokenType.PLUS || self.current.type == TokenType.MINUS)
    {
        String operator = self.current.value;
        self.consume();
        ASTNode term = self.term();

        ASTNodeList right;
        right.push(term);

        range.end = term.range.end;
        range.length = range.end - range.start;
        node =
        {
            NodeType.BIN,
            {
                .bin_node =
                {
                    operator,
                    left,
                    right
                }
            },
            range,
            line,
            context_lines
        };
    }

    return node;
}

fn ASTNode Parser.term(&self)
{
    ASTNode node = self.factor();
    ASTNodeList left;
    left.push(node);

    int line = node.line;
    List{String} context_lines = node.context_lines;
    Range range =
    {
        .start = node.range.start
    };

    while (self.current.type == TokenType.STAR || self.current.type == TokenType.SLASH)
    {
        String operator = self.current.value;
        self.consume();
        ASTNode factor = self.factor();

        ASTNodeList right;
        right.push(factor);

        range.end = factor.range.end;
        range.length = range.end - range.start;
        node =
        {
            NodeType.BIN,
            {
                .bin_node =
                {
                    operator,
                    left,
                    right
                }
            },
            range,
            line,
            context_lines
        };
    }

    return node;
}

fn ASTNode Parser.factor(&self)
{
    ASTNode node;

    switch (self.current.type)
    {
        case TokenType.INTEGER:
            node =
            {
                NodeType.INT,
                {
                    .int_node =
                    {
                        self.current.value
                    }
                },
                self.current.range,
                self.current.line,
                self.current.context_lines
            };
            self.consume();
        case TokenType.DOUBLE:
            node =
            {
                NodeType.DOUBLE,
                {
                    .double_node =
                    {
                        self.current.value
                    }
                },
                self.current.range,
                self.current.line,
                self.current.context_lines
            };
            self.consume();
        case TokenType.FLOAT:
            node =
            {
                NodeType.FLOAT,
                {
                    .float_node =
                    {
                        self.current.value
                    }
                },
                self.current.range,
                self.current.line,
                self.current.context_lines
            };
            self.consume();
        case TokenType.BOOLEAN:
            node =
            {
                NodeType.BOOL,
                {
                    .bool_node =
                    {
                        self.current.value
                    }
                },
                self.current.range,
                self.current.line,
                self.current.context_lines
            };
            self.consume();
        case TokenType.STRING:
            node =
            {
                NodeType.STR,
                {
                    .str_node =
                    {
                        self.current.value
                    }
                },
                self.current.range,
                self.current.line,
                self.current.context_lines
            };
            self.consume();
        case TokenType.LPAREN:
            self.consume();
            node = self.expr();
            self.try_consume(TokenType.RPAREN);
        default:
            errors::print(self.file_path, self.current, "expression expected");
    }

    return node;
}

fn ASTNode Parser.ext(&self)
{
    int line = self.current.line;
    List{String} context_lines = self.current.context_lines;
    Range range =
    {
        .start = self.current.range.start
    };
    self.consume();

    DString type;
    type.append_chars(self.current.value);
    self.try_consume(TokenType.IDENTIFIER);

    DString name;
    name.append_chars(self.current.value);
    self.try_consume(TokenType.IDENTIFIER);

    ASTNodeList parameters = self.def_parameters();

    DString alias_name;
    if (self.current.type == TokenType.KW_AS)
    {
        self.consume();
        alias_name.append_chars(self.current.value);
        self.try_consume(TokenType.IDENTIFIER);
    }

    range.end = self.current.range.end;
    self.try_consume(TokenType.SEMICOLON);

    return
    {
        NodeType.EXT,
        {
            .ext_node =
            {
                type.str_view(),
                name.str_view(),
                parameters,
                alias_name.str_view()
            }
        },
        range,
        line,
        context_lines
    };
}