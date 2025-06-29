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
    SWITCH,
    FLOAT,
    CONST,
    IDENT,
    FIELD,
    MACRO,
    UNARY,
    WHILE,
    FILE,
    BOOL,
    LINK,
    CALL,
    CHAR,
    INIT,
    CASE,
    USE,
    DEF,
    INT,
    STR,
    BIN,
    EXT,
    VAR,
    INC,
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
        SwitchNode       switch_node;
        FloatNode        float_node;
        ConstNode        const_node;
        IdentNode        ident_node;
        FieldNode        field_node;
        MacroNode        macro_node;
        UnaryNode        unary_node;
        WhileNode        while_node;
        FileNode         file_node;
        BoolNode         bool_node;
        CallNode         call_node;
        CharNode         char_node;
        InitNode         init_node;
        CaseNode         case_node;
        UseNode          use_node;
        DefNode          def_node;
        IntNode          int_node;
        StrNode          str_node;
        BinNode          bin_node;
        ExtNode          ext_node;
        VarNode          var_node;
        IncNode          inc_node;
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
    String   id; // TODO: change to ASTNode* for calls like `69.$size`
    ASTNode* node;
}

struct MacroNode
{
    String    type;
    String    name;
    ASTNode[] parameters;
    ASTNode[] children;
}

struct UnaryNode
{
    String   operator;
    ASTNode* expr;
}

struct WhileNode
{
    ASTNode*  condition;
    ASTNode[] children;
}

struct SwitchNode
{
    ASTNode*  expr;
    ASTNode[] cases;
}

struct CaseNode
{
    ASTNode*  condition;
    ASTNode[] children;
}

struct IncNode
{
    String name;
    String operator;
}
