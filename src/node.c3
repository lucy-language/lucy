module lucy::node;

import std;
import lucy::token;
import json::serialize;

alias ASTNodeList = List{ASTNode};
alias StringList = List{String};

enum NodeType
{
    PARAMETER,
    REASSIGN,
    RETURN,
    DOUBLE,
    GLOBAL,
    FLOAT,
    CONST,
    IDENT,
    FILE,
    BOOL,
    LINK,
    CALL,
    CHAR,
    USE,
    DEF,
    INT,
    STR,
    BIN,
    EXT,
    VAR,
}

struct JsonElement
{
    NodeType type;
    void*    node;
}

fn void? ASTNode.to_json(&self, DString* dest) {
	switch (self.node_type) {
		case PARAMETER: serialize::add_json((JsonElement){ self.node_type, &self.node.parameter_node }, dest)!;
		case REASSIGN:  serialize::add_json((JsonElement){ self.node_type, &self.node.reassign_node }, dest)!;
		case RETURN:    serialize::add_json((JsonElement){ self.node_type, &self.node.return_node }, dest)!;
		case DOUBLE:    serialize::add_json((JsonElement){ self.node_type, &self.node.double_node }, dest)!;
		case GLOBAL:    serialize::add_json((JsonElement){ self.node_type, &self.node.global_node }, dest)!;
		case FLOAT:     serialize::add_json((JsonElement){ self.node_type, &self.node.float_node }, dest)!;
		case CONST:     serialize::add_json((JsonElement){ self.node_type, &self.node.const_node }, dest)!;
		case IDENT:     serialize::add_json((JsonElement){ self.node_type, &self.node.ident_node }, dest)!;
		case FILE:      serialize::add_json((JsonElement){ self.node_type, &self.node.file_node }, dest)!;
		case BOOL:      serialize::add_json((JsonElement){ self.node_type, &self.node.bool_node }, dest)!;
		case LINK:      serialize::add_json((JsonElement){ self.node_type, &self.node.linker_option_node }, dest)!;
		case CALL:      serialize::add_json((JsonElement){ self.node_type, &self.node.call_node }, dest)!;
        case CHAR:      serialize::add_json((JsonElement){ self.node_type, &self.node.char_node }, dest)!;
		case USE:       serialize::add_json((JsonElement){ self.node_type, &self.node.use_node }, dest)!;
		case DEF:       serialize::add_json((JsonElement){ self.node_type, &self.node.def_node }, dest)!;
		case INT:       serialize::add_json((JsonElement){ self.node_type, &self.node.int_node }, dest)!;
		case STR:       serialize::add_json((JsonElement){ self.node_type, &self.node.str_node }, dest)!;
		case BIN:       serialize::add_json((JsonElement){ self.node_type, &self.node.bin_node }, dest)!;
		case EXT:       serialize::add_json((JsonElement){ self.node_type, &self.node.ext_node }, dest)!;
		case VAR:       serialize::add_json((JsonElement){ self.node_type, &self.node.var_node }, dest)!;
	}
}

struct ASTNode
{
    NodeType     node_type;
    union        node
    {
        LinkerOptionNode linker_option_node;
        ParameterNode    parameter_node;
        ReassignNode     reassign_node;
        ReturnNode       return_node;
        DoubleNode       double_node;
        GlobalNode       global_node;
        FloatNode        float_node;
        ConstNode        const_node;
        IdentNode        ident_node;
        FileNode         file_node;
        BoolNode         bool_node;
        CallNode         call_node;
        CharNode         char_node;
        UseNode          use_node;
        DefNode          def_node;
        IntNode          int_node;
        StrNode          str_node;
        BinNode          bin_node;
        ExtNode          ext_node;
        VarNode          var_node;
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
    StringList types;
    String     name;
    ASTNode[]  parameters;
    ASTNode[]  children;
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
    StringList types;
    StringList names;
    ASTNode*   value;
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
