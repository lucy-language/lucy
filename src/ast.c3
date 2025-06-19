module lucy;

import json;
import std::io;

fn void? ASTNode.to_json(&self, DString* dest, bool pretty, int indent)
{
	switch (self.node_type) {
        case INIT_VALUE: serialize::add_json(self.node.init_value_node, dest, pretty, indent)!;
		case PARAMETER:  serialize::add_json(self.node.parameter_node, dest, pretty, indent)!;
		case REASSIGN:   serialize::add_json(self.node.reassign_node, dest, pretty, indent)!;
        case ACCESS:     serialize::add_json(self.node.access_node, dest, pretty, indent)!;
		case STRUCT:     serialize::add_json(self.node.struct_node, dest, pretty, indent)!;
		case RETURN:     serialize::add_json(self.node.return_node, dest, pretty, indent)!;
		case DOUBLE:     serialize::add_json(self.node.double_node, dest, pretty, indent)!;
		case GLOBAL:     serialize::add_json(self.node.global_node, dest, pretty, indent)!;
		case FLOAT:      serialize::add_json(self.node.float_node, dest, pretty, indent)!;
		case CONST:      serialize::add_json(self.node.const_node, dest, pretty, indent)!;
		case IDENT:      serialize::add_json(self.node.ident_node, dest, pretty, indent)!;
		case FIELD:      serialize::add_json(self.node.field_node, dest, pretty, indent)!;
		case MACRO:      serialize::add_json(self.node.macro_node, dest, pretty, indent)!;
		case UNARY:      serialize::add_json(self.node.unary_node, dest, pretty, indent)!;
		case WHILE:      serialize::add_json(self.node.while_node, dest, pretty, indent)!;
		case FILE:       serialize::add_json(self.node.file_node, dest, pretty, indent)!;
		case BOOL:       serialize::add_json(self.node.bool_node, dest, pretty, indent)!;
		case LINK:       serialize::add_json(self.node.linker_option_node, dest, pretty, indent)!;
		case CALL:       serialize::add_json(self.node.call_node, dest, pretty, indent)!;
        case CHAR:       serialize::add_json(self.node.char_node, dest, pretty, indent)!;
        case INIT:       serialize::add_json(self.node.init_node, dest, pretty, indent)!;
		case USE:        serialize::add_json(self.node.use_node, dest, pretty, indent)!;
		case DEF:        serialize::add_json(self.node.def_node, dest, pretty, indent)!;
		case INT:        serialize::add_json(self.node.int_node, dest, pretty, indent)!;
		case STR:        serialize::add_json(self.node.str_node, dest, pretty, indent)!;
		case BIN:        serialize::add_json(self.node.bin_node, dest, pretty, indent)!;
		case EXT:        serialize::add_json(self.node.ext_node, dest, pretty, indent)!;
		case VAR:        serialize::add_json(self.node.var_node, dest, pretty, indent)!;
		case IF:         serialize::add_json(self.node.if_node, dest, pretty, indent)!;
	}
}

struct ParameterJson
{
    NodeType node_type;
    bool     vararg;
    String   type;
    String   name;
}

struct ReassignJson
{
    NodeType node_type;
    String   name;
    ASTNode  value;
}

struct ReturnJson
{
    NodeType  node_type;
    ASTNode[] values;
}

struct DoubleJson
{
    NodeType node_type;
    String   value;
}

struct GlobalJson
{
    NodeType node_type;
    ASTNode  node;
}

struct FloatJson
{
    NodeType node_type;
    String   value;
}

struct ConstJson
{
    NodeType node_type;
    String   type;
    String   name;
    ASTNode  value;
}

struct IdentJson
{
    NodeType node_type;
    String   name;
}

struct FileJson
{
    NodeType  node_type;
    ASTNode[] linker_options;
    String    module_name;
    ASTNode[] children;
}

struct BoolJson
{
    NodeType node_type;
    String   value;
}

struct CallJson
{
    NodeType  node_type;
    String    name;
    ASTNode[] arguments;
}

struct CharJson
{
    NodeType node_type;
    String   value;
}

struct UseJson
{
    NodeType node_type;
    String   path;
}

struct DefJson
{
    NodeType  node_type;
    String[]  types;
    String    name;
    ASTNode[] parameters;
    ASTNode[] children;
}

struct IntJson
{
    NodeType node_type;
    String   value;
}

struct StrJson
{
    NodeType node_type;
    String   value;
}

struct BinJson
{
    NodeType node_type;
    String   op;
    ASTNode  left;
    ASTNode  right;
}

struct ExtJson
{
    NodeType  node_type;
    String    type;
    String    name;
    ASTNode[] parameters;
    String    alias_name;
}

struct VarJson
{
    NodeType node_type;
    String[] types;
    String[] names;
    ASTNode  value;
}

struct VarJson2
{
    NodeType node_type;
    String[] types;
    String[] names;
    String   value;
}

struct IfJson
{
    NodeType  node_type;
    ASTNode   condition;
    ASTNode[] children;
    ASTNode   else_if;
    ASTNode[] else_children;
}

struct IfJson2
{
    NodeType  node_type;
    ASTNode   condition;
    ASTNode[] children;
    String    else_if;
    ASTNode[] else_children;
}

struct FieldJson
{
    NodeType node_type;
    String   type;
    String   name;
}

struct StructJson
{
    NodeType  node_type;
    String    name;
    ASTNode[] fields;
}

struct InitJson
{
    NodeType  node_type;
    ASTNode[] values;
}

struct InitValueJson
{
    NodeType node_type;
    String   name;
    ASTNode  value;
}

struct AccessJson
{
    NodeType node_type;
    String   id;
    ASTNode  node;
}

struct MacroJson
{
    NodeType  node_type;
    String    type;
    String    name;
    ASTNode[] parameters;
    ASTNode[] children;
}

struct UnaryJson
{
    NodeType node_type;
    String   operator;
    ASTNode  expr;
}

struct WhileJson
{
    NodeType  node_type;
    ASTNode   condition;
    ASTNode[] children;
}

fn void? ParameterNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((ParameterJson){ PARAMETER, self.vararg, self.type, self.name }, dest, pretty, indent)!;
}

fn void? ReassignNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((ReassignJson){ REASSIGN, self.name, *self.value }, dest, pretty, indent)!;
}

fn void? ReturnNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((ReturnJson){ RETURN, self.values }, dest, pretty, indent)!;
}

fn void? DoubleNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((DoubleJson){ DOUBLE, self.value }, dest, pretty, indent)!;
}

fn void? GlobalNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((GlobalJson){ GLOBAL, *self.node }, dest, pretty, indent)!;
}

fn void? FloatNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((FloatJson){ FLOAT, self.value }, dest, pretty, indent)!;
}

fn void? ConstNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((ConstJson){ CONST, self.type, self.name, *self.value}, dest, pretty, indent)!;
}

fn void? IdentNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((IdentJson){ IDENT, self.name }, dest, pretty, indent)!;
}

fn void? FileNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((FileJson){ FILE, self.linker_options, self.module_name, self.children }, dest, pretty, indent)!;
}

fn void? BoolNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((BoolJson){ BOOL, self.value }, dest, pretty, indent)!;
}

fn void? CallNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((CallJson){ CALL, self.name, self.arguments }, dest, pretty, indent)!;
}

fn void? CharNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((CharJson){ CHAR, self.value }, dest, pretty, indent)!;
}

fn void? UseNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((UseJson){ USE, self.path }, dest, pretty, indent)!;
}

fn void? DefNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((DefJson){ DEF, self.types, self.name, self.parameters, self.children }, dest, pretty, indent)!;
}

fn void? IntNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((IntJson){ INT, self.value }, dest, pretty, indent)!;
}

fn void? StrNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((StrJson){ STR, self.value }, dest, pretty, indent)!;
}

fn void? BinNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((BinJson){ BIN, self.op, *self.left, *self.right }, dest, pretty, indent)!;
}

fn void? ExtNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((ExtJson){ EXT, self.type, self.name, self.parameters, self.alias_name }, dest, pretty, indent)!;
}

fn void? VarNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    if (self.value == null)
    {
        serialize::add_json((VarJson2){ VAR, self.types, self.names, "null" }, dest, pretty, indent)!;
    } else
    {
        serialize::add_json((VarJson){ VAR, self.types, self.names, *self.value }, dest, pretty, indent)!;
    }
}

fn void? IfNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    if (self.else_if == null)
    {
        serialize::add_json((IfJson2){ IF, *self.condition, self.children, "null", self.else_children }, dest, pretty, indent)!;
    } else
    {
        serialize::add_json((IfJson){ IF, *self.condition, self.children, *self.else_if, self.else_children }, dest, pretty, indent)!;
    }
}

fn void? FieldNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((FieldJson){ FIELD, self.type, self.name }, dest, pretty, indent)!;
}

fn void? StructNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((StructJson){ STRUCT, self.name, self.fields }, dest, pretty, indent)!;
}

fn void? InitNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((InitJson){ INIT, self.values }, dest, pretty, indent)!;
}

fn void? InitValueNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((InitValueJson){ INIT_VALUE, self.name, *self.value }, dest, pretty, indent)!;
}

fn void? AccessNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((AccessJson){ ACCESS, self.id, *self.node }, dest, pretty, indent)!;
}

fn void? MacroNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((MacroJson){ MACRO, self.type, self.name, self.parameters, self.children }, dest, pretty, indent)!;
}

fn void? UnaryNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((UnaryJson){ UNARY, self.operator, *self.expr }, dest, pretty, indent)!;
}

fn void? WhileNode.to_json(&self, DString* dest, bool pretty, int indent)
{
    serialize::add_json((WhileJson){ WHILE, *self.condition, self.children }, dest, pretty, indent)!;
}
