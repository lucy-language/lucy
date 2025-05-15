module lucy::token;

import std::collections::list;
import std::core::string;

struct Range
{
    int start;
    int end;
    int length;
}

struct Token
{
    TokenType    type;
    String       value;
    Range        range;
    int          line;
    List{String} context_lines;
}

fn String Token.str_view(&self)
{
    return string::tformat("Token(%s, `%s`)", self.type, self.value);
}

enum TokenType : (String str)
{
    SEMICOLON = "`;`",
    LBRACKET  = "`[`",
    RBRACKET  = "`]`",
    PERCENT   = "`%`",
    LPAREN    = "`(`",
    RPAREN    = "`)`",
    LBRACE    = "`{`",
    RBRACE    = "`}`",
    PERIOD    = "`.`",
    COMMA     = "`,`",

    SLASH = "`/`",
    MINUS = "`+`",
    PLUS  = "`-`",
    STAR  = "`*`",

    BOOLEAN = "boolean",
    INTEGER = "integer",
    STRING  = "string",
    DOUBLE  = "double",
    FLOAT   = "float",

    KW_RETURN = "return",
    KW_PKG    = "pkg",
    KW_DEF    = "def",
    KW_USE    = "use",
    KW_EXT    = "ext",
    KW_VAR    = "var",
    KW_AS     = "as",

    IDENTIFIER = "identifier",

    EOF = "EOF"
}