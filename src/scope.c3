module lucy::scope;

import std;
import llvm;

struct Scope
{
    Scope*                        parent;
    HashMap{String, LLVMValueRef} variables;
}


fn LLVMValueRef Scope.get_var(&self, String name)
{
    if (self.variables.has_key(name))
    {
        return self.variables.get(name)!!;
    }

    if (self.parent != null)
    {
        return self.parent.get_var(name);
    }

    io::eprintfn("Could not find variable `%s`", name);
    os::exit(1);
}
