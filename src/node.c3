module lucy::node;

import std;
import lucy::token;
import json::serialize;

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

struct PkgNode       { ASTNode* path; }
struct PathNode      { ASTNode*[] segments; }
struct FileNode      { ASTNode[] linker_options; ASTNode* pkg; ASTNode*[] statements; }
struct UseNode       { ASTNode* path; }
struct ParameterNode { bool is_vararg; ASTNode* type; ASTNode* name; }
struct DefNode       { ASTNode* type; ASTNode* name; ASTNode*[] parameters; ASTNode*[] children; }
struct ReturnNode    { ASTNode*[] values; }
struct IntNode       { String value; }
struct StrNode       { String value; }
struct BinNode       { String operator; ASTNode* left; ASTNode* right; }
struct DoubleNode    { String value; }
struct FloatNode     { String value; }
struct BoolNode      { String value; }
struct ExtNode       { ASTNode* type; ASTNode* name; ASTNode*[] parameters; ASTNode* aka; }
struct LinkNode      { ASTNode* name; }
struct ConstNode     { ASTNode* type; ASTNode* name; ASTNode* value; }
struct GlobalNode    { ASTNode* node; }
struct VarNode       { ASTNode* type; ASTNode*[] names; ASTNode* value; }
struct ReassignNode  { ASTNode* name; ASTNode* value; }
struct CallNode      { ASTNode* name; ASTNode*[] arguments; }
struct IdentNode     { String name; }
struct CharNode      { String value; }
struct IfNode        { ASTNode* condition; ASTNode*[] children; ASTNode* else_if; ASTNode*[] else_children; }
struct FieldNode     { ASTNode* type; ASTNode* name; }
struct StructNode    { ASTNode* name; ASTNode*[] fields; }
struct InitNode      { ASTNode*[] values; }
struct InitValueNode { ASTNode* name; ASTNode* value; }
struct AccessNode    { ASTNode* expr; ASTNode* next; }
struct MacroNode     { ASTNode* type; ASTNode* name; ASTNode*[] parameters; ASTNode*[] children; }
struct UnaryNode     { String operator; ASTNode* expr; }
struct WhileNode     { ASTNode* condition; ASTNode*[] children; }
struct SwitchNode    { ASTNode* expression; ASTNode*[] cases; }
struct CaseNode      { ASTNode* condition; ASTNode*[] children; }
struct IncNode       { ASTNode* identifier; String operator; }
struct ForNode       { ASTNode* statement; ASTNode* condition; ASTNode* expression; ASTNode*[] children; }
struct TupleNode     { ASTNode*[] values; }
struct NullNode      { String value; }
