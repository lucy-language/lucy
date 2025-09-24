module lucy::generator;

import lucy::scope, lucy::types, lucy::node, lucy::util, lucy::linker;
import std::io;
import llvm;

struct GeneratorResult
{
    LLVMGenerator llvm;
}

fn GeneratorResult generate(TypeTable* types, String[] linked_module_paths, ASTNode* ast, Backend backend, bool emit_llvm, String path)
{
    switch (backend)
    {
        case LLVM:
            LLVMGenerator gen = llvm_gen::new(types, linked_module_paths, ast, emit_llvm, path);
            gen.generate();
            return { .llvm = gen };
        case MLIR:
        case LUCY:
        case QBE:
            util::panicf("Backend `%s` not implemented yet.", backend, file: $$FILE, line: $$LINE, function: $$FUNC);
    }

    return {};
}
