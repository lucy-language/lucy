module lucy::token;

import lucy;
import std;

struct Range
{
    int start;
    int end;
}

struct Token
{
    TokenType    type;
    String       value;
    Range        range;
    int          line;
    StringList   context_lines;
}

fn String Token.str_view(&self)
{
    return string::tformat("Token(%s, `%s`)", self.type, self.value);
}

enum TokenType : (String str)
{
    NOT_EQUAL = "`!=`",
    IS_EQUAL  = "`==`",
    GTE       = "`>=`",
    LTE       = "`<=`",
    LT        = "`>`",
    GT        = "`<`",

    SEMICOLON = "`;`",
    LBRACKET  = "`[`",
    RBRACKET  = "`]`",
    PERCENT   = "`%`",
    LPAREN    = "`(`",
    RPAREN    = "`)`",
    LBRACE    = "`{`",
    RBRACE    = "`}`",
    PERIOD    = "`.`",
    EQUALS    = "`=`",
    COMMA     = "`,`",
    COLON     = "`:`",
    AT        = "`@`",

    SLASH = "`/`",
    MINUS = "`+`",
    PLUS  = "`-`",
    STAR  = "`*`",

    BOOLEAN = "boolean",
    INTEGER = "integer",
    STRING  = "string",
    DOUBLE  = "double",
    FLOAT   = "float",
    CHAR    = "char",

    KW_RETURN = "return",
    KW_GLOBAL = "global",
    KW_CONST  = "const",
    KW_ELSE   = "else",
    KW_PKG    = "pkg",
    KW_DEF    = "def",
    KW_USE    = "use",
    KW_EXT    = "ext",
    KW_VAR    = "var",
    KW_AS     = "as",
    KW_IF     = "if",

    IDENTIFIER = "identifier",

    EOF = "EOF"
}
