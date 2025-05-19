module lucy::node;

import std::collections::list;

import lucy::token;

alias ASTNodeList = List{ASTNode};

enum NodeType
{
    PARAMETER,
    REASSIGN,
    RETURN,
    DOUBLE,
    GLOBAL,
    FLOAT,
    CONST,
    FILE,
    BOOL,
    LINK,
    USE,
    DEF,
    INT,
    STR,
    BIN,
    EXT,
    VAR,
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
    LinkerOptionNode linker_option_node;
    ParameterNode    parameter_node;
    ReassignNode     reassign_node;
    ReturnNode       return_node;
    DoubleNode       double_node;
    GlobalNode       global_node;
    FloatNode        float_node;
    ConstNode        const_node;
    FileNode         file_node;
    BoolNode         bool_node;
    UseNode          use_node;
    DefNode          def_node;
    IntNode          int_node;
    StrNode          str_node;
    BinNode          bin_node;
    ExtNode          ext_node;
    VarNode          var_node;
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

struct ConstNode
{
    String      type;
    String      name;
    ASTNodeList value;
}

struct GlobalNode
{
    ASTNodeList node;
}

struct VarNode
{
    String      type;
    String      name;
    ASTNodeList value;
}

struct ReassignNode
{
    String      name;
    ASTNodeList value;
}