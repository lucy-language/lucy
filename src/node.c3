module lucy::node;

import std;
import lucy::token;
import json::serialize;

enum NodeType
{
    INIT_VALUE,
    ATTRIBUTE,
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
    TUPLE,
    FILE,
    BOOL,
    LINK,
    CALL,
    CHAR,
    INIT,
    CASE,
    PATH,
    NULL,
    USE,
    DEF,
    INT,
    STR,
    BIN,
    EXT,
    VAR,
    INC,
    FOR,
    PKG,
    IF,
}

struct ASTNode
{
    NodeType     node_type;
    union        node
    {
        InitValueNode    init_value_node;
        AttributeNode    attribute_node;
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
        TupleNode        tuple_node;
        LinkNode         link_node;
        FileNode         file_node;
        BoolNode         bool_node;
        CallNode         call_node;
        CharNode         char_node;
        InitNode         init_node;
        CaseNode         case_node;
        PathNode         path_node;
        NullNode         null_node;
        UseNode          use_node;
        DefNode          def_node;
        IntNode          int_node;
        StrNode          str_node;
        BinNode          bin_node;
        ExtNode          ext_node;
        VarNode          var_node;
        IncNode          inc_node;
        ForNode          for_node;
        PkgNode          pkg_node;
        IfNode           if_node;
    }
    Range    range;
    int      line;
    String[] ctx;
}

struct IfNode        { ASTNode* condition; ASTNode*[] children; ASTNode* else_if; ASTNode*[] else_children; }
struct BinNode       { String operator; ASTNode* left; ASTNode* right; }
struct DefNode       { ASTNode* type; ASTNode* name; ASTNode*[] parameters; ASTNode*[] attributes; ASTNode*[] children; }
struct ExtNode       { ASTNode* type; ASTNode* name; ASTNode*[] parameters; ASTNode* aka; ASTNode*[] attributes; }
struct ForNode       { ASTNode* statement; ASTNode* condition; ASTNode* expression; ASTNode*[] children; }
struct IncNode       { ASTNode* identifier; String operator; }
struct IntNode       { String value; }
struct PkgNode       { ASTNode* path; }
struct StrNode       { String value; }
struct UseNode       { ASTNode* path; }
struct VarNode       { ASTNode* type; ASTNode*[] names; ASTNode* value; }
struct BoolNode      { String value; }
struct CallNode      { ASTNode* name; ASTNode*[] arguments; }
struct CaseNode      { ASTNode* condition; ASTNode*[] children; }
struct CharNode      { String value; }
struct FileNode      { ASTNode*[] links; ASTNode* pkg; ASTNode*[] statements; }
struct InitNode      { ASTNode*[] values; }
struct LinkNode      { ASTNode* name; }
struct NullNode      { String value; }
struct PathNode      { ASTNode*[] segments; }
struct ConstNode     { ASTNode* type; ASTNode* name; ASTNode* value; }
struct FieldNode     { ASTNode* type; ASTNode* name; }
struct FloatNode     { String value; }
struct IdentNode     { String name; }
struct MacroNode     { ASTNode* type; ASTNode* name; ASTNode*[] parameters; ASTNode*[] attributes; ASTNode*[] children; }
struct TupleNode     { ASTNode*[] values; }
struct UnaryNode     { String operator; ASTNode* expr; }
struct WhileNode     { ASTNode* condition; ASTNode*[] children; }
struct AccessNode    { ASTNode* expr; ASTNode* next; }
struct DoubleNode    { String value; }
struct GlobalNode    { ASTNode* node; }
struct ReturnNode    { ASTNode*[] values; }
struct StructNode    { ASTNode* name; ASTNode*[] fields; }
struct SwitchNode    { ASTNode* expression; ASTNode*[] cases; }
struct ReassignNode  { ASTNode* name; ASTNode* value; }
struct AttributeNode { String name; }
struct InitValueNode { ASTNode* name; ASTNode* value; }
struct ParameterNode { bool is_vararg; ASTNode* type; ASTNode* name; }
struct VariatricNode { ASTNode* node; }
