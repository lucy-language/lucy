module lucy;

import json;
import std::io;

fn void? ASTNode.to_json(&self, DString* dest)
{
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
        case CHAR:      serialize::add_json(self.node.char_node, dest)!;
		case USE:       serialize::add_json(self.node.use_node, dest)!;
		case DEF:       serialize::add_json(self.node.def_node, dest)!;
		case INT:       serialize::add_json(self.node.int_node, dest)!;
		case STR:       serialize::add_json(self.node.str_node, dest)!;
		case BIN:       serialize::add_json(self.node.bin_node, dest)!;
		case EXT:       serialize::add_json(self.node.ext_node, dest)!;
		case VAR:       serialize::add_json(self.node.var_node, dest)!;
	}
}

struct ParameterJson
{
    String node_type;
    bool   vararg;
    String type;
    String name;
}

struct ReassignJson
{
    String  node_type;
    String  name;
    ASTNode value;
}

struct ReturnJson
{
    String    node_type;
    ASTNode[] values;
}

struct DoubleJson
{
    String node_type;
    String value;
}

struct GlobalJson
{
    String  node_type;
    ASTNode node;
}

struct FloatJson
{
    String node_type;
    String value;
}

struct ConstJson
{
    String  node_type;
    String  type;
    String  name;
    ASTNode value;
}

struct IdentJson
{
    String node_type;
    String name;
}

struct FileJson
{
    String    node_type;
    ASTNode[] linker_options;
    String    module_name;
    ASTNode[] children;
}

struct BoolJson
{
    String node_type;
    String value;
}

struct CallJson
{
    String    node_type;
    String    name;
    ASTNode[] arguments;
}

struct CharJson
{
    String node_type;
    String value;
}

struct UseJson
{
    String node_type;
    String path;
}

struct DefJson
{
    String    node_type;
    String[]  types;
    String    name;
    ASTNode[] parameters;
    ASTNode[] children;
}

struct IntJson
{
    String node_type;
    String value;
}

struct StrJson
{
    String node_type;
    String value;
}

struct BinJson
{
    String  node_type;
    String  op;
    ASTNode left;
    ASTNode right;
}

struct ExtJson
{
    String    node_type;
    String    type;
    String    name;
    ASTNode[] parameters;
    String    alias_name;
}

struct VarJson
{
    String   node_type;
    String[] types;
    String[] names;
    ASTNode  value;
}

fn void? ParameterNode.to_json(&self, DString* dest)
{
    serialize::add_json((ParameterJson){ "PARAMETER", self.vararg, self.type, self.name }, dest)!;
}

fn void? ReassignNode.to_json(&self, DString* dest)
{
    serialize::add_json((ReassignJson){ "REASSIGN", self.name, *self.value }, dest)!;
}

fn void? ReturnNode.to_json(&self, DString* dest)
{
    serialize::add_json((ReturnJson){ "RETURN", self.values }, dest)!;
}

fn void? DoubleNode.to_json(&self, DString* dest)
{
    serialize::add_json((DoubleJson){ "DOUBLE", self.value }, dest)!;
}

fn void? GlobalNode.to_json(&self, DString* dest)
{
    serialize::add_json((GlobalJson){ "GLOBAL", *self.node }, dest)!;
}

fn void? FloatNode.to_json(&self, DString* dest)
{
    serialize::add_json((FloatJson){ "FLOAT", self.value }, dest)!;
}

fn void? ConstNode.to_json(&self, DString* dest)
{
    serialize::add_json((ConstJson){ "CONST", self.type, self.name, *self.value}, dest)!;
}

fn void? IdentNode.to_json(&self, DString* dest)
{
    serialize::add_json((IdentJson){ "IDENT", self.name }, dest)!;
}

fn void? FileNode.to_json(&self, DString* dest)
{
    serialize::add_json((FileJson){ "FILE", self.linker_options, self.module_name, self.children }, dest)!;
}

fn void? BoolNode.to_json(&self, DString* dest)
{
    serialize::add_json((BoolJson){ "BOOL", self.value }, dest)!;
}

fn void? CallNode.to_json(&self, DString* dest)
{
    serialize::add_json((CallJson){ "CALL", self.name, self.arguments }, dest)!;
}

fn void? CharNode.to_json(&self, DString* dest)
{
    serialize::add_json((CharJson){ "CHAR", self.value }, dest)!;
}

fn void? UseNode.to_json(&self, DString* dest)
{
    serialize::add_json((UseJson){ "USE", self.path }, dest)!;
}

fn void? DefNode.to_json(&self, DString* dest)
{
    serialize::add_json((DefJson){ "DEF", self.types, self.name, self.parameters, self.children }, dest)!;
}

fn void? IntNode.to_json(&self, DString* dest)
{
    serialize::add_json((IntJson){ "INT", self.value }, dest)!;
}

fn void? StrNode.to_json(&self, DString* dest)
{
    serialize::add_json((StrJson){ "STR", self.value }, dest)!;
}

fn void? BinNode.to_json(&self, DString* dest)
{
    serialize::add_json((BinJson){ "BIN", self.op, *self.left, *self.right }, dest)!;
}

fn void? ExtNode.to_json(&self, DString* dest)
{
    serialize::add_json((ExtJson){ "EXT", self.type, self.name, self.parameters, self.alias_name }, dest)!;
}

fn void? VarNode.to_json(&self, DString* dest)
{
    serialize::add_json((VarJson){ "VAR", self.types, self.names, *self.value }, dest)!;
}
