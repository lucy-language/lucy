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
    TokenType type;
    String    value;
    Range     range;
    int       line;
    String[]  ctx;
}

enum TokenType : const String
{
    NOT_EQUAL = "`!=`",
    IS_EQUAL  = "`==`",
    GTE       = "`>=`",
    LTE       = "`<=`",
    AND       = "`&&`",
    OR        = "`||`",
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
    BANG      = "`!`",
    AT        = "`@`",

    SLASH = "`/`",
    MINUS = "`-`",
    PLUS  = "`+`",
    STAR  = "`*`",

    BOOLEAN = "boolean",
    INTEGER = "integer",
    STRING  = "string",
    DOUBLE  = "double",
    FLOAT   = "float",
    CHAR    = "char",

    KW_RETURN = "return",
    KW_GLOBAL = "global",
    KW_STRUCT = "struct",
    KW_SWITCH = "switch",
    KW_CONST  = "const",
    KW_MACRO  = "macro",
    KW_WHILE  = "while",
    KW_ELSE   = "else",
    KW_CASE   = "case",
    KW_LINK   = "link",
    KW_NULL   = "null",
    KW_PKG    = "pkg",
    KW_DEF    = "def",
    KW_USE    = "use",
    KW_EXT    = "ext",
    KW_VAR    = "var",
    KW_FOR    = "for",
    KW_AS     = "as",
    KW_IF     = "if",

    IDENTIFIER = "identifier",
    ATTRIBUTE  = "attribute",

    EOF = "EOF"
}
