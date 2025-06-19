module lucy::node;

import std;
import lucy::token;
import json::serialize;

alias StringList = List{String};

enum NodeType
{
    INIT_VALUE,
    PARAMETER,
    REASSIGN,
    ACCESS,
    STRUCT,
    RETURN,
    DOUBLE,
    GLOBAL,
    FLOAT,
    CONST,
    IDENT,
    FIELD,
    MACRO,
    FILE,
    BOOL,
    LINK,
    CALL,
    CHAR,
    INIT,
    USE,
    DEF,
    INT,
    STR,
    BIN,
    EXT,
    VAR,
    IF,
}

struct JsonElement
{
    NodeType type;
    void*    node;
}

struct ASTNode
{
    NodeType     node_type;
    union        node
    {
        LinkerOptionNode linker_option_node;
        InitValueNode    init_value_node;
        ParameterNode    parameter_node;
        ReassignNode     reassign_node;
        AccessNode       access_node;
        StructNode       struct_node;
        ReturnNode       return_node;
        DoubleNode       double_node;
        GlobalNode       global_node;
        FloatNode        float_node;
        ConstNode        const_node;
        IdentNode        ident_node;
        FieldNode        field_node;
        MacroNode        macro_node;
        FileNode         file_node;
        BoolNode         bool_node;
        CallNode         call_node;
        CharNode         char_node;
        InitNode         init_node;
        UseNode          use_node;
        DefNode          def_node;
        IntNode          int_node;
        StrNode          str_node;
        BinNode          bin_node;
        ExtNode          ext_node;
        VarNode          var_node;
        IfNode           if_node;
    }
    Range        range;
    int          line;
    StringList   context_lines;
}

struct FileNode
{
    ASTNode[] linker_options;
    String    module_name;
    ASTNode[] children;
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
    String[]  types;
    String    name;
    ASTNode[] parameters;
    ASTNode[] children;
}

struct ReturnNode
{
    ASTNode[] values;
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
    String   op;
    ASTNode* left;
    ASTNode* right;
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
    String    type;
    String    name;
    ASTNode[] parameters;
    String    alias_name;
}

struct LinkerOptionNode
{
    String   value;
    String[] platforms;
}

struct ConstNode
{
    String      type;
    String      name;
    ASTNode*    value;
}

struct GlobalNode
{
    ASTNode* node;
}

struct VarNode
{
    String[] types;
    String[] names;
    ASTNode* value;
}

struct ReassignNode
{
    String   name;
    ASTNode* value;
}

struct CallNode
{
    String      name;
    ASTNode[] arguments;
}

struct IdentNode
{
    String name;
}

struct CharNode
{
    String value;
}

struct IfNode
{
    ASTNode*  condition;
    ASTNode[] children;
    ASTNode*  else_if;
    ASTNode[] else_children;
}

struct FieldNode
{
    String type;
    String name;
}

struct StructNode
{
    String    name;
    ASTNode[] fields;
}

struct InitNode
{
    ASTNode[] values;
}

struct InitValueNode
{
    String   name;
    ASTNode* value;
}

struct AccessNode
{
    String   id;
    ASTNode* node;
}

struct MacroNode
{
    String    type;
    String    name;
    ASTNode[] parameters;
    ASTNode[] children;
}
