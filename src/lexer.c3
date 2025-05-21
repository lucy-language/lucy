module lucy::lexer;

import std::collections::list;
import std::core::dstring;
import std::ascii;
import std::io;

import lucy::token;
import lucy::util;

alias TokenList = List{Token};

struct Lexer
{
    String text;
    int    pos;
    char   current;
    int    line;
    int    column;
}

fn Lexer new(String text)
{
    if (text.len == 0)
    {
        return
        {
            .text    = text,
            .pos     = 0,
            .current = '\0',
            .line    = 1,
            .column  = 0
        };
    }

    return
    {
        .text    = text,
        .pos     = 0,
        .current = text[0],
        .line    = 1,
        .column  = 0
    };
}

fn void Lexer.consume(&self)
{
    self.pos++;
    if (self.pos < self.text.len)
    {
        self.current = self.text[self.pos];
    } else
    {
        self.current = '\0';
    }
}

fn char Lexer.peek(&self)
{
    return self.text[self.pos + 1];
}

fn TokenList Lexer.tokenize(&self)
{
    TokenList tokens;

    while (self.current != '\0')
    {
        while (self.current.is_space())
        {
            self.column++;

            if (self.current.in({ '\n', '\r' }))
            {
                self.column = 0;
                self.line++;
            }
            self.consume();
        }

        if (self.current == ';') { tokens.push({ SEMICOLON, ";", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == '.') { tokens.push({ PERIOD,    ".", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == ',') { tokens.push({ COMMA,     ",", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == '(') { tokens.push({ LPAREN,    "(", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == ')') { tokens.push({ RPAREN,    ")", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == '{') { tokens.push({ LBRACE,    "{", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == '}') { tokens.push({ RBRACE,    "}", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == '[') { tokens.push({ LBRACKET,  "[", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == ']') { tokens.push({ RBRACKET,  "]", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == '%') { tokens.push({ PERCENT,   "%", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == '@') { tokens.push({ AT,        "@", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == '=') { tokens.push({ EQUALS,    "=", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == ':') { tokens.push({ COLON,     ":", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }

        if (self.current == '+') { tokens.push({ PLUS,   "+", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == '-') { tokens.push({ MINUS,  "-", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == '*') { tokens.push({ STAR,   "*", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }
        if (self.current == '/') { tokens.push({ SLASH,  "/", { self.column, self.column + 1 }, self.line, self.get_context_lines() }); self.consume(); self.column++; }

        if (self.current == '#')
        {
            while (self.current != '\0' && !self.current.in({ '\n', '\r' }))
            {
                self.consume();
            }
        }

        if (self.current == '"') tokens.push(self.string());
        if (self.current.is_digit()) tokens.push(self.number());
        if (self.current == '$' || self.current.is_alpha()) tokens.push(self.identifier());
    }

    tokens.push({ EOF, "EOF", { self.column, self.column }, self.line, self.get_context_lines() });

    return tokens;
}

fn Token Lexer.string(&self)
{
    DString result;
    int start = self.column;

    self.column++;
    self.consume();

    while (self.current != '"')
    {
        result.append_char(self.current);
        self.column++;
        self.consume();
    }
    self.column++;
    self.consume();

    return { STRING, result.str_view(), { start, self.column }, self.line, self.get_context_lines() };
}

fn Token Lexer.number(&self)
{
    DString result;
    int start = self.column;

    if (self.current == '0' && self.peek().in({ 'x', 'X' }))
    {
        result.append_char(self.current);
        self.consume();
        result.append_char(self.current);
        self.consume();
        self.column += 2;

        while (self.current.is_digit() || self.current.in(util::LOWERCASE[0..5]) || self.current.in(util::UPPERCASE[0..5]))
        {
            result.append_char(self.current);
            self.column++;
            self.consume();
        }

        return { INTEGER, result.str_view(), { start, self.column }, self.line, self.get_context_lines() };
    }

    while (self.current.is_digit())
    {
        result.append_char(self.current);
        self.column++;
        self.consume();
    }

    bool has_decimal_or_exponent = false;
    if (self.current == '.')
    {
        has_decimal_or_exponent = true;
        result.append_char(self.current);
        self.column++;
        self.consume();

        while (self.current.is_digit())
        {
            result.append_char(self.current);
            self.column++;
            self.consume();
        }
    }

    if (self.current.in({ 'e', 'E' }))
    {
        has_decimal_or_exponent = true;
        result.append_char(self.current);
        self.column++;
        self.consume();

        if (self.current.in({ '+', '-' }))
        {
            result.append_char(self.current);
            self.column++;
            self.consume();
        }

        while (self.current.is_digit())
        {
            result.append_char(self.current);
            self.column++;
            self.consume();
        }
    }

    if (self.current.in({ 'f', 'F' }))
    {
        self.column++;
        self.consume();
        return { FLOAT, result.str_view(), { start, self.column }, self.line, self.get_context_lines() };
    }

    if (!has_decimal_or_exponent)
    {
        return { INTEGER, result.str_view(), { start, self.column }, self.line, self.get_context_lines() };
    }

    return { DOUBLE, result.str_view(), { start, self.column }, self.line, self.get_context_lines() };
}

fn Token Lexer.identifier(&self)
{
    DString result;
    int start = self.column;

    while (self.current.is_alnum() || self.current.in({ '_', '$' }))
    {
        result.append_char(self.current);
        self.column++;
        self.consume();
    }

    String str = result.str_view();

    if (str.in({ "true", "false" }))
    {
        return { BOOLEAN, str, { start, self.column }, self.line, self.get_context_lines() };
    }

    if (str == "as")     return { KW_AS, str, { start, self.column }, self.line, self.get_context_lines() };
    if (str == "pkg")    return { KW_PKG, str, { start, self.column }, self.line, self.get_context_lines() };
    if (str == "def")    return { KW_DEF, str, { start, self.column }, self.line, self.get_context_lines() };
    if (str == "use")    return { KW_USE, str, { start, self.column }, self.line, self.get_context_lines() };
    if (str == "ext")    return { KW_EXT, str, { start, self.column }, self.line, self.get_context_lines() };
    if (str == "var")    return { KW_VAR, str, { start, self.column }, self.line, self.get_context_lines() };
    if (str == "const")  return { KW_CONST, str, { start, self.column }, self.line, self.get_context_lines() };
    if (str == "return") return { KW_RETURN, str, { start, self.column }, self.line, self.get_context_lines() };
    if (str == "global") return { KW_GLOBAL, str, { start, self.column }, self.line, self.get_context_lines() };

    return { IDENTIFIER, str, { start, self.column }, self.line, self.get_context_lines() };
}

fn List{String} Lexer.get_context_lines(&self)
{
    int error_line = self.line;
    List{String} context_lines;
    int current_pos = 0;
    int current_line = 1;
    int line_start = 0;
    int text_len = self.text.len;

    int start_line = max(1, error_line - 3);

    while (current_pos < text_len && current_line <= error_line)
    {
        if (current_line >= start_line)
        {
            int line_end = current_pos;
            while (line_end < text_len && self.text[line_end] != '\n' && self.text[line_end] != '\r')
            {
                line_end++;
            }

            if (line_start <= line_end && line_end < text_len)
            {
                context_lines.push(self.text[line_start..line_end]);
            }
        }

        while (current_pos < text_len && self.text[current_pos] != '\n' && self.text[current_pos] != '\r')
        {
            current_pos++;
        }

        if (current_pos < text_len)
        {
            if (self.text[current_pos] == '\r')
            {
                current_pos++;
                if (current_pos < text_len && self.text[current_pos] == '\n')
                {
                    current_pos++;
                }
            } else
            {
                current_pos++;
            }
        }

        current_line++;
        line_start = current_pos;
    }

    return context_lines;
}