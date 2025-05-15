module lucy::compiler;

import std::io;

import lucy::parser;
import lucy::node;

import llvm;
import lucy::errors;


struct Compiler
{
    FileNode       file_node;
    String         module_name;
    String         file_path;
    LLVMModuleRef  mod;
    LLVMBuilderRef builder;
}

fn Compiler new(Parser parser)
{
    ASTNode file = parser.parse();
    String mod_name = file.node.file_node.module_name;
    LLVMModuleRef mod = llvm::module_create_with_name(mod_name);
    LLVMBuilderRef builder = llvm::create_builder();

    return
    {
        .file_node   = file.node.file_node,
        .module_name = mod_name,
        .file_path   = parser.file_path,
        .mod         = mod,
        .builder     = builder
    };
}

fn void Compiler.compile(&self)
{
    defer llvm::dispose_builder(self.builder);
    foreach (ast : self.file_node.children)
    {
        self.compile_node(ast);
    }
}

fn void Compiler.compile_node(&self, ASTNode ast)
{
    switch (ast.node_type)
    {
        case NodeType.DEF: self.compile_def(ast.node.def_node);
        case NodeType.RETURN: self.compile_return(ast.node.return_node);
        case NodeType.EXT: self.compile_ext(ast.node.ext_node);
        default: break;
    }
}

fn void Compiler.compile_def(&self, DefNode node)
{
    LLVMTypeRef type;

    switch (node.type)
    {
        case "void": type = llvm::void_type();
        case "double": type = llvm::double_type();
        case "float": type = llvm::float_type();
        case "bool": type = llvm::int1_type();
        case "int": type = llvm::int32_type();
    }

    LLVMTypeRef fn_type = llvm::function_type(type, null, 0, 0);
    LLVMValueRef fN = llvm::add_function(self.mod, node.name, fn_type);

    LLVMBasicBlockRef entry_block = llvm::append_basic_block(fN, "entry");
    llvm::position_builder_at_end(self.builder, entry_block);

    foreach (child : node.children)
    {
        self.compile_node(child);
    }

    char* error;
    if (llvm::print_module_to_file(self.mod, string::tformat("%s.ll", self.module_name), &error))
    {
        io::eprintfn("Failed to write IR: %s", *error);
        llvm::dispose_message(error);
        return;
    }
}

fn void Compiler.compile_return(&self, ReturnNode node)
{
    LLVMTypeRef type = llvm::int32_type(); // TODO: figure out type from expression

    ASTNode value = node.value[0];

    // TODO: catch error early
    if (catch value.node.int_node.value.to_long())
    {
        errors::print_node(self.file_path, value, "int expected, got string");
    }

    // TODO: assume value is INT for now
    LLVMValueRef value_ref = llvm::const_int(type, value.node.int_node.value.to_int(), 0)!!;
    llvm::build_ret(self.builder, value_ref);
}

fn void Compiler.compile_ext(&self, ExtNode node)
{
    LLVMTypeRef int_type = llvm::int32_type();
    LLVMTypeRef str_type = llvm::pointer_type(llvm::int8_type(), 0);
    LLVMTypeRef[] printf_args = {str_type};

    bool vararg;

    foreach (param : node.parameters)
    {
        if (param.node.parameter_node.vararg)
        {
            vararg = true;
            break;
        }
    }

    LLVMTypeRef printf_type = llvm::function_type(int_type, printf_args, 1, vararg ? 1 : 0);
    llvm::add_function(self.mod, node.name, printf_type);
}