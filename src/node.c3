module lucy::node;

import std::collections::list;

import lucy::token;

alias ASTNodeList = List{ASTNode};

enum NodeType
{
    FILE,
    USE,
    PARAMETER,
    DEF,
    RETURN,
    INT,
    STR,
    BIN,
    DOUBLE,
    FLOAT,
    BOOL,
    EXT,
    LINK
}

struct ASTNode
{
    NodeType     node_type;
    Node         node;
    Range        range;
    int          line;
    List{String} context_lines;
}

union Node
{
    FileNode         file_node;
    UseNode          use_node;
    ParameterNode    parameter_node;
    DefNode          def_node;
    ReturnNode       return_node;
    IntNode          int_node;
    StrNode          str_node;
    BinNode          bin_node;
    DoubleNode       double_node;
    FloatNode        float_node;
    BoolNode         bool_node;
    ExtNode          ext_node;
    LinkerOptionNode linker_option_node;
}

struct FileNode
{
    String      module_name;
    ASTNodeList children;
}

struct UseNode
{
    String path;
}

struct ParameterNode
{
    bool   vararg;
    String type;
    String name;
}

struct DefNode
{
    String      type;
    String      name;
    ASTNodeList parameters;
    ASTNodeList children;
}

struct ReturnNode
{
    ASTNodeList value;
}

struct IntNode
{
    String value;
}

struct StrNode
{
    String value;
}

struct BinNode
{
    String      op;
    ASTNodeList left;
    ASTNodeList right;
}

struct DoubleNode
{
    String value;
}

struct FloatNode
{
    String value;
}

struct BoolNode
{
    String value;
}

struct ExtNode
{
    String      type;
    String      name;
    ASTNodeList parameters;
    String      alias_name;
}

struct LinkerOptionNode
{
    String value;
}