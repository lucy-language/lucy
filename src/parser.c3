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
        util::array_insert(&children, self.use());
    }

    while (self.current.type != EOF)
    {
        
        switch (self.current.type)
        {
            case KW_DEF:    util::array_insert(&children, self.def());
            case KW_EXT:    util::array_insert(&children, self.ext());
            case KW_CONST:  util::array_insert(&children, self.const_stmt());
            case KW_MACRO:  util::array_insert(&children, self.macro_stmt());
            case KW_GLOBAL: util::array_insert(&children, self.global());
            case KW_STRUCT: util::array_insert(&children, self.struct_stmt());
            default: errors::print(self.file_path, self.current, string::tformat("statement expected, got %s", self.current.type.str));
        }
    }

    self.try_consume(EOF);

    return { .node_type = FILE, .node.file_node = { linker_options, module_name, children } };
}

fn ASTNode[] Parser.linker_options(&self)
{
    ASTNode[] linker_options = mem::new_array(ASTNode, 0);

    while (self.current.type == KW_LINK)
    {
        int line = self.current.line;
        int start = self.current.range.start;
        StringList context_lines = self.current.context_lines;
        self.consume();
        self.try_consume(LT);

        String value = self.current.value;

        self.try_consume(IDENTIFIER);
        self.try_consume(GT);

        String[] platforms;

        while (self.current.type == AT)
        {
            self.consume();
            util::array_insert(&platforms, self.current.value);
            self.try_consume(IDENTIFIER);
        }

        int end = self.current.range.end;
        self.try_consume(SEMICOLON);

        util::array_insert(&linker_options, (ASTNode){ LINK, { .linker_option_node = { value, platforms } }, { start, end }, line, context_lines });
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

    String[] types;
    if (self.current.type == LPAREN)
    {
        self.consume();

        util::array_insert(&types, self.current.value);
        self.try_consume(IDENTIFIER);

        self.try_consume(COMMA);

        util::array_insert(&types, self.current.value);
        self.try_consume(IDENTIFIER);

        while (self.current.type == COMMA)
        {
            self.consume();

            util::array_insert(&types, self.current.value);
            self.try_consume(IDENTIFIER);
        }

        self.try_consume(RPAREN);
    } else
    {
        util::array_insert(&types, self.current.value);
        self.try_consume(IDENTIFIER);
    }

    String name = self.def_name();
    int end = self.tokens[(usz)self.pos - 1].range.end;

    ASTNode[] parameters = self.def_parameters();
    ASTNode[] children = self.body();
    
    return { DEF, { .def_node = { types, name, parameters, children } }, { start, end }, line, context_lines };
}

fn ASTNode[] Parser.body(&self, bool include_braces = true, TokenType[] delimiters = {RBRACE})
{
    ASTNode[] body = mem::new_array(ASTNode, 0);

    if (include_braces)
    {
        self.try_consume(LBRACE);
    }

    while (!util::in(delimiters, self.current.type))
    {
        util::array_insert(&body, self.statement());
    }

    if (include_braces)
    {
        self.try_consume(RBRACE);
    }

    return body;
}

fn ASTNode Parser.statement(&self)
{
    switch (self.current.type)
    {
        case KW_VAR:     return self.var_stmt();
        case KW_IF:      return self.if_stmt();
        case KW_WHILE:   return self.while_stmt();
        case IDENTIFIER:
            ASTNode node = self.identifier();
            self.try_consume(SEMICOLON);
            return node;
        case KW_SWITCH: return self.switch_stmt();
        case KW_RETURN: return self.return_stmt();
        case KW_FOR:    return self.for_stmt();
        default: errors::print(self.file_path, self.current, string::tformat("statement expected, got %s", self.current.type.str));
    }
    return {};
}

fn ASTNode Parser.if_stmt(&self)
{
    int line = self.current.line;
    StringList context_lines = self.current.context_lines;
    int start = self.current.range.start;
    int end = self.current.range.end;
    
    self.consume();
    self.try_consume(LPAREN);
    
    ASTNode* condition = malloc(ASTNode.sizeof);
    *condition = self.condition();

    self.try_consume(RPAREN);
    
    ASTNode[] children      = self.body();
    ASTNode[] else_children = mem::new_array(ASTNode, 0);
    ASTNode*  else_if;

    if (self.current.type == KW_ELSE)
    {
        self.consume();
        if (self.current.type == KW_IF)
        {
            else_if = malloc(ASTNode.sizeof);
            *else_if = self.if_stmt();
        } else
        {
            else_children = self.body();
        }
    }

    return { IF, { .if_node = { condition, children, else_if, else_children } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.condition(&self)
{
    ASTNode node = self.expr();
    ASTNode* left = malloc(ASTNode.sizeof);
    *left = node;

    int line = node.line;
    StringList context_lines = node.context_lines;
    int start = node.range.start;

    while (util::in((TokenType[]){IS_EQUAL, NOT_EQUAL, GTE, LTE, GT, LT}, self.current.type))
    {
        String operator = self.current.value;
        self.consume();

        ASTNode* right = malloc(ASTNode.sizeof);
        *right = self.expr();

        int end = right.range.end;
        node = { BIN, { .bin_node = { operator, left, right } }, { start, end }, line, context_lines };
    }

    return node;
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
        String type;

        if (self.current.type == KW_VAR)
        {
            self.consume();
            vararg = true;
        }

        type = self.type();

        int end = self.current.range.end;
        String name = self.current.value;
        self.try_consume(IDENTIFIER);

        util::array_insert(&parameters, (ASTNode){ PARAMETER, { .parameter_node = { vararg, type, name } }, { start, end }, line, context_lines });

        while (self.current.type == COMMA)
        {
            self.consume();

            int other_line = self.current.line;
            int other_start = self.current.range.start;
            StringList other_context_lines = self.current.context_lines;
            bool other_vararg;
            String other_type;

            if (self.current.type == KW_VAR)
            {
                self.consume();
                other_vararg = true;
            }

            other_type = self.type();

            int other_end = self.current.range.end;
            String other_name = self.current.value;
            self.try_consume(IDENTIFIER);

            util::array_insert(&parameters, (ASTNode){ PARAMETER, { .parameter_node = { other_vararg, other_type, other_name } }, { other_start, other_end }, other_line, other_context_lines });
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
        case LBRACE:
            node = self.initializer();
        case PLUS:
        case MINUS:
        case STAR:
        case BANG:
            String operator = self.current.value;
            int start = self.current.range.start;
            self.consume();
            ASTNode* expr = malloc(ASTNode.sizeof);
            *expr = self.expr();
            int end = (*expr).range.end;
            node = { UNARY, { .unary_node = { operator, expr } }, { start, end }, self.current.line, self.current.context_lines };
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

    String type = self.type();
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
        case KW_DEF:    *node = self.def();
        case KW_EXT:    *node = self.ext();
        case KW_CONST:  *node = self.const_stmt();
        case KW_MACRO:  *node = self.macro_stmt();
        case KW_STRUCT: *node = self.struct_stmt();
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

    String[] types;
    if (self.current.type == LPAREN)
    {
        self.consume();

        util::array_insert(&types, self.type());
        self.try_consume(COMMA);

        util::array_insert(&types, self.type());
        while (self.current.type == COMMA)
        {
            self.consume();
            util::array_insert(&types, self.type());
        }

        self.try_consume(RPAREN);
    } else
    {
        util::array_insert(&types, self.type());
    }

    String[] names;
    util::array_insert(&names, self.current.value);
    self.try_consume(IDENTIFIER);

    while (self.current.type == COMMA)
    {
        self.consume();
        util::array_insert(&names, self.current.value);
        self.try_consume(IDENTIFIER);
    }
    
    int end = self.current.range.end;

    if (self.current.type == EQUALS)
    {
        self.consume();
        ASTNode* value = malloc(ASTNode.sizeof);
        *value = self.condition();
        self.try_consume(SEMICOLON);
        return { VAR, { .var_node = { types, names, value } }, { start, end }, line, context_lines };
    }

    self.try_consume(SEMICOLON);

    return { VAR, { .var_node = { types, names, null } }, { start, end }, line, context_lines };
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
        util::array_insert(&values, self.expr());

        while (self.current.type == COMMA)
        {
            self.consume();
            util::array_insert(&values, self.expr());
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

        return { REASSIGN, { .reassign_node = { id, value } }, { start, end }, line, context_lines };
    }

    if (self.current.type == LPAREN)
    {
        self.consume();

        ASTNode[] arguments;

        if (self.current.type != RPAREN)
        {
            util::array_insert(&arguments, self.condition());
        }

        while (self.current.type == COMMA)
        {
            self.consume();
            util::array_insert(&arguments, self.condition());
        }

        int end = self.current.range.end;
        self.try_consume(RPAREN);

        return { CALL, { .call_node = { id, arguments } }, { start, end }, line, context_lines };
    }

    if (self.current.type == PERIOD)
    {
        self.consume();
        ASTNode* node = malloc(ASTNode.sizeof);
        *node = self.identifier();
        int end = node.range.end;
        return { ACCESS, { .access_node = { id, node } }, { start, end }, line, context_lines };
    }

    if (util::in((TokenType[]){BANG, PLUS, MINUS}, self.current.type) && util::in((TokenType[]){BANG, PLUS, MINUS}, self.tokens[(usz)self.pos + 1].type))
    {
        String operator = self.current.value;
        TokenType type = self.current.type;
        self.consume();

        int end = self.current.range.end;
        self.try_consume(type);
        return { INC, { .inc_node = { id, operator } }, { start, end }, line, context_lines };
    }

    int end = self.tokens[(usz)self.pos - 1].range.end;
    return { IDENT, { .ident_node = { id } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.struct_stmt(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    StringList context_lines = self.current.context_lines;
    self.consume();
    
    String name = self.current.value;
    self.try_consume(IDENTIFIER);
    ASTNode[] fields = mem::new_array(ASTNode, 0);
    
    self.try_consume(LBRACE);

    while (self.current.type != RBRACE)
    {
        int field_line = self.current.line;
        int field_start = self.current.range.start;
        StringList field_context_lines = self.current.context_lines;
        String field_type = self.type();

        String field_name = self.current.value;
        self.try_consume(IDENTIFIER);

        int field_end = self.current.range.end;
        self.try_consume(SEMICOLON);
        util::array_insert(&fields, (ASTNode){ FIELD, { .field_node = { field_type, field_name } }, { field_start, field_end }, field_line, field_context_lines });
    }

    int end = self.current.range.end;
    self.try_consume(RBRACE);

    return { STRUCT, { .struct_node = { name, fields } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.initializer(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    StringList context_lines = self.current.context_lines;
    self.consume();
    
    ASTNode[] values = mem::new_array(ASTNode, 0);

    if (self.current.type != RBRACE)
    {
        int value_line  = self.current.line;
        int value_start = self.current.range.start;
        StringList value_context_lines = self.current.context_lines;

        String name;
        if (self.current.type == PERIOD)
        {
            self.consume();
            name = self.current.value;
            self.try_consume(IDENTIFIER);
            self.try_consume(EQUALS);
        }

        ASTNode* value = malloc(ASTNode.sizeof);
        *value = self.expr();
        int value_end = (*value).range.end;

        util::array_insert(&values, (ASTNode){ INIT_VALUE, { .init_value_node = { name, value } }, { value_start, value_end }, value_line, value_context_lines });

        while (self.current.type == COMMA)
        {
            self.consume();
            int other_value_line  = self.current.line;
            int other_value_start = self.current.range.start;
            StringList other_value_context_lines = self.current.context_lines;

            String other_name;
            if (self.current.type == PERIOD)
            {
                self.consume();
                other_name = self.current.value;
                self.try_consume(IDENTIFIER);
                self.try_consume(EQUALS);
            }

            ASTNode* other_value = malloc(ASTNode.sizeof);
            *other_value = self.expr();
            int other_value_end = (*other_value).range.end;

            util::array_insert(&values, (ASTNode){ INIT_VALUE, { .init_value_node = { other_name, other_value } }, { other_value_start, other_value_end }, other_value_line, other_value_context_lines });
        }
    }
    
    int end = self.current.range.end;
    self.try_consume(RBRACE);

    return { INIT, { .init_node = { values } }, { start, end }, line, context_lines };
}

fn String Parser.type(&self)
{
    DString type;
    defer type.free();

    type.append_chars(self.current.value);
    self.try_consume(IDENTIFIER);

    while (util::in((TokenType[]){LBRACKET, STAR}, self.current.type))
    {
        if (self.current.type == LBRACKET)
        {
            type.append_chars("[");
            self.consume();
            if (self.current.type == INTEGER)
            {
                type.append_chars(self.current.value);
                self.consume();
            }
            type.append_chars("]");
            self.try_consume(RBRACKET);
        } else
        {
            self.consume();
            type.append_char('*');
        }
    }

    return type.copy_str(mem);
}

fn ASTNode Parser.macro_stmt(&self)
{
    int line                 = self.current.line;
    int start                = self.current.range.start;
    StringList context_lines = self.current.context_lines;
    self.consume();
    
    String type;
    String name;
    String type_or_name = self.type();
    if (self.current.type == IDENTIFIER)
    {
        type = type_or_name;
        name = self.current.value;
        self.consume();
    } else
    {
        name = type_or_name;
    }

    int end = self.tokens[(usz)self.pos - 1].range.end;

    ASTNode[] parameters = self.macro_parameters();
    ASTNode[] body       = self.body();

    return { MACRO, { .macro_node = { type, name, parameters, body } }, { start, end }, line, context_lines };
}

fn ASTNode[] Parser.macro_parameters(&self)
{
    ASTNode[] parameters;
    self.try_consume(LPAREN);

    if (self.current.type == IDENTIFIER)
    {
        int line                 = self.current.line;
        int start                = self.current.range.start;
        StringList context_lines = self.current.context_lines;
        bool vararg;

        if (self.current.type == KW_VAR)
        {
            vararg = true;
            self.consume();
        }

        String type;
        String name;
        String type_or_name = self.type();
        if (self.current.type == IDENTIFIER)
        {
            type = type_or_name;
            name = self.current.value;
            self.consume();
        } else
        {
            name = type_or_name;
        }
        int end = self.tokens[(usz)self.pos - 1].range.end;

        util::array_insert(&parameters, (ASTNode){ PARAMETER, { .parameter_node = { vararg, type, name } }, { start, end }, line, context_lines });

        while (self.current.type == COMMA)
        {
            self.consume();
            
            int other_line                 = self.current.line;
            int other_start                = self.current.range.start;
            StringList other_context_lines = self.current.context_lines;
            bool other_vararg;

            if (self.current.type == KW_VAR)
            {
                other_vararg = true;
                self.consume();
            }

            String other_type;
            String other_name;
            String other_type_or_name = self.type();
            if (self.current.type == IDENTIFIER)
            {
                other_type = other_type_or_name;
                other_name = self.current.value;
                self.consume();
            } else
            {
                other_name = other_type_or_name;
            }
            int other_end = self.tokens[(usz)self.pos - 1].range.end;

            util::array_insert(&parameters, (ASTNode){ PARAMETER, { .parameter_node = { other_vararg, other_type, other_name } }, { other_start, other_end }, other_line, other_context_lines });
        }
    }

    self.try_consume(RPAREN);
    return parameters;
}

fn ASTNode Parser.while_stmt(&self)
{
    int line = self.current.line;
    int start = self.current.range.start;
    StringList context_lines = self.current.context_lines;
    self.consume();

    self.try_consume(LPAREN);
    ASTNode* condition = malloc(ASTNode.sizeof);
    *condition = self.condition();
    int end = self.current.range.end;
    self.try_consume(RPAREN);

    ASTNode[] children = self.body();

    return { WHILE, { .while_node = { condition, children } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.switch_stmt(&self)
{
    int          line          = self.current.line;
    int          start         = self.current.range.start;
    int          end           = self.current.range.end;
    List{String} context_lines = self.current.context_lines;
    self.consume();
    self.try_consume(LPAREN);
    ASTNode* expr = malloc(ASTNode.sizeof);
    *expr         = self.expr();

    self.try_consume(RPAREN);
    ASTNode[] cases = mem::new_array(ASTNode, 0);
    
    self.try_consume(LBRACE);

    while (self.current.type == KW_CASE)
    {
        int          case_line          = self.current.line;
        int          case_start         = self.current.range.start;
        List{String} case_context_lines = self.current.context_lines;
        self.consume();
        ASTNode* case_expr = malloc(ASTNode.sizeof);
        *case_expr         = self.expr();

        int case_end = self.current.range.end;
        self.try_consume(COLON);
        ASTNode[] case_children = self.body(false, delimiters: { KW_CASE, RBRACE });

        util::array_insert(&cases, (ASTNode){ CASE, { .case_node = { case_expr, case_children } }, { case_start, case_end }, case_line, case_context_lines });
    }
    self.try_consume(RBRACE);
    return { SWITCH, { .switch_node = { expr, cases } }, { start, end }, line, context_lines };
}

fn ASTNode Parser.for_stmt(&self)
{
    int        line          = self.current.line;
    int        start         = self.current.range.start;
    int        end           = self.current.range.end;
    StringList context_lines = self.current.context_lines;

    self.consume();
    self.try_consume(LPAREN);

    int        statement_line          = self.current.line;
    int        statement_start         = self.current.range.start;
    StringList statement_context_lines = self.current.context_lines;

    ASTNode* statement = malloc(ASTNode.sizeof);
    String   type      = self.type();
    String   name      = self.current.value;
    self.try_consume(IDENTIFIER);
    self.try_consume(EQUALS);
    ASTNode* value = malloc(ASTNode.sizeof);
    *value         = self.condition();

    int statement_end = self.current.range.end;
    self.try_consume(SEMICOLON);

    String[] types = mem::new_array(String, 1);
    types[0] = type;
    String[] names = mem::new_array(String, 1);
    names[0] = name;
    *statement = { VAR, { .var_node = { types, names, value } }, { statement_start, statement_end }, statement_line, statement_context_lines };

    int        condition_line          = self.current.line;
    int        condition_start         = self.current.range.start;
    StringList condition_context_lines = self.current.context_lines;
    
    ASTNode* condition = malloc(ASTNode.sizeof);
    *condition         = self.condition();

    int condition_end = self.current.range.end;
    self.try_consume(SEMICOLON);

    int        expression_line          = self.current.line;
    int        expression_start         = self.current.range.start;
    StringList expression_context_lines = self.current.context_lines;
    
    ASTNode* expression = malloc(ASTNode.sizeof);
    *expression         = self.expr();

    int expression_end = expression.range.end;

    self.try_consume(RPAREN);

    ASTNode[] children = self.body();

    return { FOR, { .for_node = { statement, condition, expression, children } }, { start, end }, line, context_lines };
}
