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
    USE,
    DEF,
    INT,
    STR,
    BIN,
    EXT,
    VAR,
}

fn void? ASTNode.to_json(&self, DString* dest) {
	switch (self.node_type) {
		case PARAMETER: serialize::add_json(self.node.parameter_node, dest)!;
		case REASSIGN:  serialize::add_json(self.node.reassign_node, dest)!;
		case RETURN:    serialize::add_json(self.node.return_node, dest)!;
		case DOUBLE:    serialize::add_json(self.node.double_node, dest)!;
		case GLOBAL:    serialize::add_json(self.node.global_node, dest)!;
		case FLOAT:     serialize::add_json(self.node.float_node, dest)!;
		case CONST:     serialize::add_json(self.node.const_node, dest)!;
		case IDENT:     serialize::add_json(self.node.ident_node, dest)!;
		case FILE:      serialize::add_json(self.node.file_node, dest)!;
		case BOOL:      serialize::add_json(self.node.bool_node, dest)!;
		case LINK:      serialize::add_json(self.node.linker_option_node, dest)!;
		case CALL:      serialize::add_json(self.node.call_node, dest)!;
		case USE:       serialize::add_json(self.node.use_node, dest)!;
		case DEF:       serialize::add_json(self.node.def_node, dest)!;
		case INT:       serialize::add_json(self.node.int_node, dest)!;
		case STR:       serialize::add_json(self.node.str_node, dest)!;
		case BIN:       serialize::add_json(self.node.bin_node, dest)!;
		case EXT:       serialize::add_json(self.node.ext_node, dest)!;
		case VAR:       serialize::add_json(self.node.var_node, dest)!;
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
    StringList types;
    String       name;
    ASTNodeList  parameters;
    ASTNodeList  children;
}

struct ReturnNode
{
    ASTNodeList values;
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
    StringList  types;
    StringList  names;
    ASTNodeList value;
}

struct ReassignNode
{
    String      name;
    ASTNodeList value;
}

struct CallNode
{
    String      name;
    ASTNodeList arguments;
}

struct IdentNode
{
    String name;
}