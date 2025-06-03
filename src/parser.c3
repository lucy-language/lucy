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
        errors::print(self.file_path, self.current, string::tformat("%s expected, got %s", type.str, self.current.type.str));
    }
}

fn ASTNode Parser.parse(&self)
{
    ASTNode[] children = mem::new_array(ASTNode, 0);
    ASTNode[] linker_options = self.linker_options();

    String module_name = self.pkg();
    
    int i = 0;
    while (self.current.type == KW_USE)
    {
        children = util::array_insert(ASTNode,children, self.use());
    }

    while (self.current.type != EOF)
    {
        
        switch (self.current.type)
        {
            case KW_DEF: children =  util::array_insert(ASTNode, children, self.def());
            case KW_EXT: children = util::array_insert(ASTNode, children, self.ext());
            case KW_CONST: children = util::array_insert(ASTNode, children, self.const_stmt());
            case KW_GLOBAL: children = util::array_insert(ASTNode, children, self.global());
            default: errors::print(self.file_path, self.current, string::tformat("statement expected, got %s", self.current.type.str));
        }
    }

    self.try_consume(EOF);

    return { .node_type = FILE, .node.file_node = { linker_options, module_name, children } };
}

fn ASTNode[] Parser.linker_options(&self)
{
    ASTNode[] linker_options = mem::new_array(ASTNode, 0);

    while (self.current.type == PERCENT)
    {
        int line = self.current.line;
        int start = self.current.range.start;
        StringList context_lines = self.current.context_lines;
        self.consume();

        DString value;
        defer value.free();
        value.append_chars(self.current.value);

        self.try_consume(STRING);

        String[] platforms;

        while (self.current.type == AT)
        {
            self.consume();
            platforms = util::array_insert(String, platforms, self.current.value);
            self.try_consume(IDENTIFIER);
        }

        int end = self.current.range.end;
        self.try_consume(SEMICOLON);

        linker_options = util::array_insert(ASTNode, linker_options, (ASTNode){ LINK, { .linker_option_node = { value.copy_str(mem), platforms } }, { start, end }, line, context_lines });
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
    StringList context_lines = self.current.context_lines;
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
    StringList context_lines = self.current.context_lines;
    self.consume();

    StringList types;
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

    ASTNode[] parameters = self.def_parameters();
    ASTNode[] children = mem::new_array(ASTNode, 0);

    self.try_consume(LBRACE);

    while (self.current.type != RBRACE)
    {
        switch (self.current.type)
        {
            case KW_VAR: children = util::array_insert(ASTNode, children ,self.var_stmt());
            case IDENTIFIER:
                children = util::array_insert(ASTNode, children, self.identifier());
                self.try_consume(SEMICOLON);
            case KW_RETURN: children = util::array_insert(ASTNode, children, self.return_stmt());
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

fn ASTNode[] Parser.def_parameters(&self)
{
    ASTNode[] parameters;

    self.try_consume(LPAREN);

    if (self.current.type != RPAREN)
    {
        int line = self.current.line;
        int start = self.current.range.start;
        StringList context_lines = self.current.context_lines;
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

        util::array_insert(ASTNode, parameters, (ASTNode){ PARAMETER, { .parameter_node = { vararg, type.copy_str(mem), name } }, { start, end }, line, context_lines });

        while (self.current.type == COMMA)
        {
            self.consume();

            int other_line = self.current.line;
            int other_start = self.current.range.start;
            StringList other_context_lines = self.current.context_lines;
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

            util::array_insert(ASTNode, parameters, (ASTNode){ PARAMETER, { .parameter_node = { other_vararg, other_type.copy_str(mem), other_name } }, { other_start, other_end }, other_line, other_context_lines });
        }
    }

    self.try_consume(RPAREN);

    return parameters;
}

fn ASTNode Parser.expr(&self)
{
    ASTNode node = self.term();
    ASTNode* left = malloc(ASTNode.sizeof);
    *left = node;

    int line = node.line;
    StringList context_lines = node.context_lines;
    int start = node.range.start;

    while (self.current.type == PLUS || self.current.type == MINUS)
    {
        String operator = self.current.value;
        self.consume();

        ASTNode* right = malloc(ASTNode.sizeof);
        *right = self.term();

        int end = right.range.end;
        node = { BIN, { .bin_node = { operator, left, right } }, { start, end }, line, context_lines };
    }

    return node;
}

fn ASTNode Parser.term(&self)
{
    ASTNode node = self.factor();
    ASTNode* left = malloc(ASTNode.sizeof);
    *left = node;

    int line = node.line;
    StringList context_lines = node.context_lines;
    int start = node.range.start;

    while (self.current.type == STAR || self.current.type == SLASH)
    {
        String operator = self.current.value;
        self.consume();

        ASTNode* right = malloc(ASTNode.sizeof);
        *right = self.factor();

        int end = right.range.end;
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
            node = { INT, { .int_node = { self.current.value.copy(mem) } }, self.current.range, self.current.line, self.current.context_lines };
            self.consume();
        case DOUBLE:
            node = { DOUBLE, { .double_node = { self.current.value.copy(mem) } }, self.current.range, self.current.line, self.current.context_lines };
            self.consume();
        case FLOAT:
            node = { FLOAT, { .float_node = { self.current.value.copy(mem) } }, self.current.range, self.current.line, self.current.context_lines };
            self.consume();
        case BOOLEAN:
            node = { BOOL, { .bool_node = { self.current.value.copy(mem) } }, self.current.range, self.current.line, self.current.context_lines };
            self.consume();
        case STRING:
            node = { STR, { .str_node = { self.current.value.copy(mem) } }, self.current.range, self.current.line, self.current.context_lines };
            self.consume();
        case CHAR:
            node = { CHAR, { .char_node = { self.current.value.copy(mem) } }, self.current.range, self.current.line, self.current.context_lines };
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
    StringList context_lines = self.current.context_lines;
    int start = self.current.range.start;
    self.consume();

    String type = self.current.value;
    self.try_consume(IDENTIFIER);

    String name = self.current.value;
    self.try_consume(IDENTIFIER);

    ASTNode[] parameters = self.def_parameters();

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
    StringList context_lines = self.current.context_lines;
    int start = self.current.range.start;
    self.consume();

    String type = self.current.value;
    self.try_consume(IDENTIFIER);

    String name = self.current.value;
    self.try_consume(IDENTIFIER);

    self.try_consume(EQUALS);
    ASTNode* value = malloc(ASTNode.sizeof);
    *value = self.expr();

    int end = self.current.range.end;
    self.try_consume(SEMICOLON);

    return { CONST, { .const_node = { type, name, value } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.global(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    StringList context_lines = self.current.context_lines;
    self.consume();
    ASTNode* node = malloc(ASTNode.sizeof);

    switch (self.current.type)
    {
        case KW_DEF: *node = self.def();
        case KW_EXT: *node = self.ext();
        case KW_CONST: *node = self.const_stmt();
        default: errors::print(self.file_path, self.current, string::tformat("statement expected, got %s", self.current.type.str));
    }

    int end = node.range.end;

    return { GLOBAL, { .global_node = { node } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.var_stmt(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    StringList context_lines = self.current.context_lines;
    self.consume();

    StringList types;
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

    StringList names;
    names.push(self.current.value);
    self.try_consume(IDENTIFIER);

    while (self.current.type == COMMA)
    {
        self.consume();
        names.push(self.current.value);
        self.try_consume(IDENTIFIER);
    }

    ASTNode* value = malloc(ASTNode.sizeof);

    if (self.current.type == EQUALS)
    {
        self.consume();
        *value = self.expr();
    }

    int end = self.current.range.end;
    self.try_consume(SEMICOLON);

    return { VAR, { .var_node = { types, names, value } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.return_stmt(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    StringList context_lines = self.current.context_lines;
    self.consume();

    ASTNode[] values;
    if (self.current.type != SEMICOLON)
    {
        values = util::array_insert(ASTNode, values, self.expr());

        while (self.current.type == COMMA)
        {
            self.consume();
            values = util::array_insert(ASTNode, values, self.expr());
        }
    }

    int end = self.current.range.end;
    self.try_consume(SEMICOLON);

    return { RETURN, { .return_node = { values } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.identifier(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    StringList context_lines = self.current.context_lines;
    String id = self.current.value;
    self.consume();

    if (self.current.type == EQUALS)
    {
        self.consume();
        ASTNode* value = malloc(ASTNode.sizeof);
        *value = self.expr();

        int end = self.current.range.end;
        self.try_consume(SEMICOLON);

        return { REASSIGN, { .reassign_node = { id, value } }, { start, end }, line, context_lines };
    }

    if (self.current.type == LPAREN)
    {
        self.consume();

        ASTNode[] arguments;

        if (self.current.type != RPAREN)
        {
            arguments = util::array_insert(ASTNode, arguments, self.expr());
        }

        while (self.current.type == COMMA)
        {
            self.consume();
            arguments = util::array_insert(ASTNode, arguments, self.expr());
        }

        int end = self.current.range.end;
        self.try_consume(RPAREN);

        return { CALL, { .call_node = { id, arguments } }, { start, end }, line, context_lines };
    }

    int end = self.tokens[(usz)self.pos - 1].range.end;
    return { IDENT, { .ident_node = { id } }, { start, end }, line, context_lines };
}
