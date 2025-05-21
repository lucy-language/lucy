module lucy::parser;

import std;
import lucy;

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
    defer file_path.free();

    return
    {
        .tokens    = tokens,
        .pos       = pos,
        .current   = tokens[pos],
        .file_path = file_path.str_view().copy(mem)
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
        errors::print(self.file_path, self.current, string::tformat("%s expected, got %s", type.str,
                                                                            self.current.type.str));
    }
}

fn ASTNode Parser.parse(&self)
{
    ASTNodeList children;
    ASTNodeList linker_options = self.linker_options();

    String module_name = self.pkg();

    while (self.current.type == KW_USE)
    {
        children.push(self.use());
    }

    while (self.current.type != EOF)
    {
        switch (self.current.type)
        {
            case KW_DEF: children.push(self.def());
            case KW_EXT: children.push(self.ext());
            case KW_CONST: children.push(self.const_stmt());
            case KW_GLOBAL: children.push(self.global());
            default: errors::print(self.file_path, self.current, string::tformat("statement expected, got %s", self.current.type.str));
        }
    }

    self.try_consume(EOF);

    return { .node_type = FILE, .node.file_node = { module_name, children } };
}

fn ASTNodeList Parser.linker_options(&self)
{
    ASTNodeList linker_options;

    while (self.current.type == PERCENT)
    {
        int line = self.current.line;
        int start = self.current.range.start;
        List{String} context_lines = self.current.context_lines;
        self.consume();

        DString value;
        defer value.free();
        value.append_chars(self.current.value);

        self.try_consume(STRING);

        List{String} platforms;

        while (self.current.type == AT)
        {
            self.consume();
            platforms.push(self.current.value);
            self.try_consume(IDENTIFIER);
        }

        int end = self.current.range.end;
        self.try_consume(SEMICOLON);

        linker_options.push({ LINK, { .linker_option_node = { value.copy_str(mem) } }, { start, end }, line,
                                                                                           context_lines });
    }

    return linker_options;
}

fn String Parser.pkg(&self)
{
    self.try_consume(KW_PKG);

    String module_name = self.path();

    self.try_consume(SEMICOLON);

    return module_name;
}

fn ASTNode Parser.use(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    List{String} context_lines = self.current.context_lines;
    self.try_consume(KW_USE);

    String path = self.path();

    int end = self.current.range.end;
    self.try_consume(SEMICOLON);

    return { USE, { .use_node = { path } }, { start, end }, line, context_lines };
}

fn String Parser.path(&self)
{
    DString path;
    defer path.free();

    path.append_chars(self.current.value);
    self.try_consume(IDENTIFIER);

    while (self.current.type == PERIOD)
    {
        path.append_char('.');
        self.consume();
        path.append_chars(self.current.value);
        self.try_consume(IDENTIFIER);
    }

    return path.copy_str(mem);
}

fn ASTNode Parser.def(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    List{String} context_lines = self.current.context_lines;
    self.consume();

    List{String} types;
    if (self.current.type == LBRACE)
    {
        self.consume();

        types.push(self.current.value);
        self.try_consume(IDENTIFIER);

        self.try_consume(COMMA);

        types.push(self.current.value);
        self.try_consume(IDENTIFIER);

        while (self.current.type == COMMA)
        {
            self.consume();

            types.push(self.current.value);
            self.try_consume(IDENTIFIER);
        }

        self.try_consume(RBRACE);
    } else
    {
        types.push(self.current.value);
        self.try_consume(IDENTIFIER);
    }

    String name = self.def_name();
    int end = self.tokens[(usz)self.pos - 1].range.end;

    ASTNodeList parameters = self.def_parameters();

    ASTNodeList children;

    self.try_consume(LBRACE);

    while (self.current.type != RBRACE)
    {
        switch (self.current.type)
        {
            case KW_VAR: children.push(self.var_stmt());
            case IDENTIFIER: children.push(self.identifier());
            case KW_RETURN: children.push(self.return_stmt());
            default: errors::print(self.file_path, self.current, string::tformat("statement expected, got %s", self.current.type.str));
        }
    }

    self.try_consume(RBRACE);

    return { DEF, { .def_node = { types, name, parameters, children } }, { start, end }, line, context_lines };
}

fn String Parser.def_name(&self)
{
    DString name;
    defer name.free();

    name.append_chars(self.current.value);
    self.try_consume(IDENTIFIER);

    if (self.current.type == PERIOD)
    {
        name.append_char('.');
        self.consume();
        name.append_chars(self.current.value);
        self.try_consume(IDENTIFIER);
    }

    return name.copy_str(mem);
}

fn ASTNodeList Parser.def_parameters(&self)
{
    ASTNodeList parameters;

    self.try_consume(LPAREN);

    if (self.current.type != RPAREN)
    {
        int line = self.current.line;
        int start = self.current.range.start;
        List{String} context_lines = self.current.context_lines;
        bool vararg;
        DString type;
        defer type.free();

        if (self.current.type == KW_VAR)
        {
            self.consume();
            vararg = true;
        }

        type.append_chars(self.current.value);
        self.try_consume(IDENTIFIER);

        if (self.current.type == LBRACKET)
        {
            self.consume();
            self.try_consume(RBRACKET);

            type.append_chars("[]");
        }

        int end = self.current.range.end;
        String name = self.current.value;
        self.try_consume(IDENTIFIER);

        parameters.push({ PARAMETER, { .parameter_node = { vararg, type.copy_str(mem), name } }, { start, end },
                                                                                         line, context_lines });

        while (self.current.type == COMMA)
        {
            self.consume();

            int other_line = self.current.line;
            int other_start = self.current.range.start;
            List{String} other_context_lines = self.current.context_lines;
            bool other_vararg;
            DString other_type;
            defer other_type.free();

            if (self.current.type == KW_VAR)
            {
                self.consume();
                other_vararg = true;
            }

            other_type.append_chars(self.current.value);
            self.try_consume(IDENTIFIER);

            if (self.current.type == LBRACKET)
            {
                self.consume();
                self.try_consume(RBRACKET);

                other_type.append_chars("[]");
            }

            int other_end = self.current.range.end;
            String other_name = self.current.value;
            self.try_consume(IDENTIFIER);

            parameters.push({ PARAMETER, { .parameter_node = { other_vararg, other_type.copy_str(mem), other_name } },
                                                       { other_start, other_end }, other_line, other_context_lines });
        }
    }

    self.try_consume(RPAREN);

    return parameters;
}

fn ASTNode Parser.expr(&self)
{
    ASTNode node = self.term();
    ASTNodeList left;
    left.push(node);

    int line = node.line;
    List{String} context_lines = node.context_lines;
    int start = node.range.start;

    while (self.current.type == PLUS || self.current.type == MINUS)
    {
        String operator = self.current.value;
        self.consume();
        ASTNode term = self.term();

        ASTNodeList right;
        right.push(term);

        int end = term.range.end;
        node = { BIN, { .bin_node = { operator, left, right } }, { start, end }, line, context_lines };
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
    int start = node.range.start;

    while (self.current.type == STAR || self.current.type == SLASH)
    {
        String operator = self.current.value;
        self.consume();
        ASTNode factor = self.factor();

        ASTNodeList right;
        right.push(factor);

        int end = factor.range.end;
        node = { BIN, { .bin_node = { operator, left, right } }, { start, end }, line, context_lines};
    }

    return node;
}

fn ASTNode Parser.factor(&self)
{
    ASTNode node;

    switch (self.current.type)
    {
        case INTEGER:
            node = { INT, { .int_node = { self.current.value } }, self.current.range, self.current.line,
                                                                           self.current.context_lines };
            self.consume();
        case DOUBLE:
            node = { DOUBLE, { .double_node = { self.current.value } }, self.current.range, self.current.line,
                                                                                 self.current.context_lines };
            self.consume();
        case FLOAT:
            node = { FLOAT, { .float_node = { self.current.value } }, self.current.range, self.current.line,
                                                                               self.current.context_lines };
            self.consume();
        case BOOLEAN:
            node = { BOOL, { .bool_node = { self.current.value } }, self.current.range, self.current.line,
                                                                             self.current.context_lines };
            self.consume();
        case STRING:
            node = { STR, { .str_node = { self.current.value } }, self.current.range, self.current.line,
                                                                           self.current.context_lines };
            self.consume();
        case LPAREN:
            self.consume();
            node = self.expr();
            node.range.start -= 1;
            self.try_consume(RPAREN);
        case IDENTIFIER:
            node = self.identifier();
        default:
            errors::print(self.file_path, self.current, "expression expected");
    }

    return node;
}

fn ASTNode Parser.ext(&self)
{
    int line = self.current.line;
    List{String} context_lines = self.current.context_lines;
    int start = self.current.range.start;
    self.consume();

    String type = self.current.value;
    self.try_consume(IDENTIFIER);

    String name = self.current.value;
    self.try_consume(IDENTIFIER);

    ASTNodeList parameters = self.def_parameters();

    String alias_name;
    if (self.current.type == KW_AS)
    {
        self.consume();
        alias_name = self.current.value;
        self.try_consume(IDENTIFIER);
    }

    int end = self.current.range.end;
    self.try_consume(SEMICOLON);

    return { EXT, { .ext_node = { type, name, parameters, alias_name } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.const_stmt(&self)
{
    int line = self.current.line;
    List{String} context_lines = self.current.context_lines;
    int start = self.current.range.start;
    self.consume();

    String type = self.current.value;
    self.try_consume(IDENTIFIER);

    String name = self.current.value;
    self.try_consume(IDENTIFIER);

    self.try_consume(EQUALS);
    ASTNodeList value;
    value.push(self.expr());

    int end = self.current.range.end;
    self.try_consume(SEMICOLON);

    return { CONST, { .const_node = { type, name, value } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.global(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    List{String} context_lines = self.current.context_lines;
    self.consume();
    ASTNodeList node;

    switch (self.current.type)
    {
        case KW_DEF: node.push(self.def());
        case KW_EXT: node.push(self.ext());
        case KW_CONST: node.push(self.const_stmt());
        default: errors::print(self.file_path, self.current, string::tformat("statement expected, got %s", self.current.type.str));
    }

    int end = node[0].range.end;

    return { GLOBAL, { .global_node = { node } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.var_stmt(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    List{String} context_lines = self.current.context_lines;
    self.consume();

    List{String} types;
    if (self.current.type == LBRACE)
    {
        self.consume();

        types.push(self.current.value);
        self.try_consume(IDENTIFIER);

        self.try_consume(COMMA);

        types.push(self.current.value);
        self.try_consume(IDENTIFIER);

        while (self.current.type == COMMA)
        {
            self.consume();

            types.push(self.current.value);
            self.try_consume(IDENTIFIER);
        }

        self.try_consume(RBRACE);
    } else
    {
        types.push(self.current.value);
        self.try_consume(IDENTIFIER);
    }

    List{String} names;
    names.push(self.current.value);
    self.try_consume(IDENTIFIER);

    while (self.current.type == COMMA)
    {
        self.consume();
        names.push(self.current.value);
        self.try_consume(IDENTIFIER);
    }

    ASTNodeList value;

    if (self.current.type == EQUALS)
    {
        self.consume();
        value.push(self.expr());
    }

    int end = self.current.range.end;
    self.try_consume(SEMICOLON);

    return { VAR, { .var_node = { types, names, value } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.return_stmt(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    List{String} context_lines = self.current.context_lines;
    self.consume();

    ASTNodeList values;
    values.push(self.expr());

    while (self.current.type == COMMA)
    {
        self.consume();
        values.push(self.expr());
    }

    int end = self.current.range.end;
    self.try_consume(SEMICOLON);

    return { RETURN, { .return_node = { values } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.identifier(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    List{String} context_lines = self.current.context_lines;
    String id = self.current.value;
    self.consume();

    if (self.current.type == EQUALS)
    {
        self.consume();
        ASTNodeList value;
        value.push(self.expr());

        int end = self.current.range.end;
        self.try_consume(SEMICOLON);

        return { REASSIGN, { .reassign_node = { id, value } }, { start, end }, line, context_lines };
    }

    if (self.current.type == LPAREN)
    {
        self.consume();

        ASTNodeList arguments;

        if (self.current.type != RPAREN)
        {
            arguments.push(self.expr());
        }

        while (self.current.type == COMMA)
        {
            self.consume();
            arguments.push(self.expr());
        }

        int end = self.current.range.end;
        self.try_consume(RPAREN);

        return { CALL, { .call_node = { id, arguments } }, { start, end }, line, context_lines };
    }

    int end = self.tokens[(usz)self.pos - 1].range.end;
    return { IDENT, { .ident_node = { id } }, { start, end }, line, context_lines };
}