module llvm;

extern fn LLVMModuleRef module_create_with_name(char* module_id) @extern("LLVMModuleCreateWithName");
extern fn void module_dispose(LLVMModuleRef m) @extern("LLVMModuleDispose");
extern fn void dump_module(LLVMModuleRef m) @extern("LLVMDumpModule");
extern fn LLVMContextRef context_create() @extern("LLVMContextCreate");
extern fn void context_dispose(LLVMContextRef c) @extern("LLVMContextDispose");
extern fn LLVMTypeRef int1_type() @extern("LLVMInt1Type");
extern fn LLVMTypeRef int8_type() @extern("LLVMInt8Type");
extern fn LLVMTypeRef int32_type() @extern("LLVMInt32Type");
extern fn LLVMTypeRef int64_type() @extern("LLVMInt64Type");
extern fn LLVMTypeRef float_type() @extern("LLVMFloatType");
extern fn LLVMTypeRef double_type() @extern("LLVMDoubleType");
extern fn LLVMTypeRef void_type() @extern("LLVMVoidType");
extern fn LLVMTypeRef pointer_type(LLVMTypeRef element_type, usz address_space) @extern("LLVMPointerType");
extern fn LLVMTypeRef function_type(LLVMTypeRef return_type, LLVMTypeRef * param_types, usz param_count, int is_var_arg) @extern("LLVMFunctionType");
extern fn LLVMValueRef add_function(LLVMModuleRef m, char * name, LLVMTypeRef ty) @extern("LLVMAddFunction");
extern fn LLVMValueRef get_named_function(LLVMModuleRef m, char * name) @extern("LLVMGetNamedFunction");
extern fn LLVMBasicBlockRef append_basic_block(LLVMValueRef fN, char * name) @extern("LLVMAppendBasicBlock");
extern fn LLVMBasicBlockRef get_insert_block(LLVMBuilderRef builder) @extern("LLVMGetInsertBlock");
extern fn void position_builder(LLVMBuilderRef builder, LLVMBasicBlockRef block, LLVMValueRef instr) @extern("LLVMPositionBuilder");
extern fn void position_builder_at_end(LLVMBuilderRef builder, LLVMBasicBlockRef block) @extern("LLVMPositionBuilderAtEnd");
extern fn LLVMBuilderRef create_builder() @extern("LLVMCreateBuilder");
extern fn void dispose_builder(LLVMBuilderRef builder) @extern("LLVMDisposeBuilder");
extern fn LLVMValueRef build_ret_void(LLVMBuilderRef builder) @extern("LLVMBuildRetVoid");
extern fn LLVMValueRef build_ret(LLVMBuilderRef builder, LLVMValueRef v) @extern("LLVMBuildRet");
extern fn LLVMValueRef build_add(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, char * name) @extern("LLVMBuildAdd");
extern fn LLVMValueRef build_load(LLVMBuilderRef builder, LLVMValueRef ptr, char * name) @extern("LLVMBuildLoad");
extern fn LLVMValueRef const_int(LLVMTypeRef ty, ulong n, int sign_extend) @extern("LLVMConstInt");
extern fn LLVMValueRef const_real(LLVMTypeRef ty, double n) @extern("LLVMConstReal");
extern fn LLVMValueRef const_string(char* str, usz len, LLVMBool dont_null_terminate) @extern("LLVMConstString");
extern fn LLVMValueRef const_struct(LLVMValueRef * constant_vals, usz count, int packed) @extern("LLVMConstStruct");
extern fn int link_in_mcjit() @extern("LLVMLinkInMCJIT");
extern fn int link_in_interpreter() @extern("LLVMLinkInInterpreter");
extern fn int create_execution_engine_for_module(LLVMExecutionEngineRef * ee, LLVMModuleRef m, char * * error) @extern("LLVMCreateExecutionEngineForModule");
extern fn int run_function(LLVMExecutionEngineRef ee, LLVMValueRef f, usz num_args, LLVMGenericValueRef * args) @extern("LLVMRunFunction");
extern fn int print_module_to_file(LLVMModuleRef m, char* filename, char** rrror_message) @extern("LLVMPrintModuleToFile");
extern fn void dispose_message(char* message) @extern("LLVMDisposeMessage");
extern fn LLVMValueRef get_param(LLVMValueRef fN, usz index) @extern("LLVMGetParam");
extern fn void set_value_name(LLVMValueRef val, char* name) @extern("LLVMSetValueName");
extern fn LLVMValueRef add_global(LLVMModuleRef mod, LLVMTypeRef type, char* name) @extern("LLVMAddGlobal");
extern fn LLVMValueRef set_initializer(LLVMValueRef global_var, LLVMValueRef constant_val) @extern("LLVMSetInitializer");
extern fn void set_linkage(LLVMValueRef global, LLVMLinkage linkage) @extern("LLVMSetLinkage");
extern fn void set_global_constant(LLVMValueRef global, LLVMBool is_constant) @extern("LLVMSetGlobalConstant");
extern fn void set_unnamed_addr(LLVMValueRef global, LLVMBool has_unnamed_addr) @extern("LLVMSetUnnamedAddr");
extern fn LLVMTypeRef type_of(LLVMValueRef val) @extern("LLVMTypeOf");
extern fn LLVMValueRef build_alloca(LLVMBuilderRef builder, LLVMTypeRef type, char* name) @extern("LLVMBuildAlloca");
extern fn void build_store(LLVMBuilderRef builder, LLVMValueRef val, LLVMValueRef variable) @extern("LLVMBuildStore");

alias LLVMBool = CInt;
alias LLVMContextRef = void * ;
alias LLVMModuleRef = void * ;
alias LLVMTypeRef = void * ;
alias LLVMValueRef = void * ;
alias LLVMBasicBlockRef = void * ;
alias LLVMBuilderRef = void * ;
alias LLVMPassManagerRef = void * ;
alias LLVMPassRegistryRef = void * ;
alias LLVMMemoryBufferRef = void * ;
alias LLVMOpaquePassManagerBuilder = void * ;
alias LLVMPassManagerBuilderRef = LLVMOpaquePassManagerBuilder * ;
alias LLVMExecutionEngineRef = void * ;
alias LLVMTargetDataRef = void * ;
alias LLVMTargetMachineRef = void * ;
alias LLVMTargetRef = void * ;
alias LLVMTargetLibraryInfoRef = void * ;
alias LLVMGenericValueRef = void * ;
alias LLVMMCJITMemoryManagerRef = void * ;
alias LLVMOpcode = CUInt;
alias LLVMDiagnosticInfoRef = void * ;
alias LLVMComdatRef = void * ;
alias LLVMMetadataRef = void * ;
alias LLVMNamedMDNodeRef = void * ;
alias LLVMValueMetadataEntry = void * ;
alias LLVMInlineAsmDialect = CUInt;
alias LLVMAttributeRef = void * ;

enum LLVMLinkage
{
    EXTERNAL_LINKAGE,
    AVAILABLE_EXTERNALLY_LINKAGE,
    LINK_ONCE_ANY_LINKAGE,
    LINK_ONCE_ODR_LINKAGE,
    WEAK_ANY_LINKAGE,
    WEAK_ODR_LINKAGE,
    APPENDING_LINKAGE,
    INTERNAL_LINKAGE,
    PRIVATE_LINKAGE,
    DLL_IMPORT_LINKAGE,
    DLL_EXPORT_LINKAGE,
    EXTERNAL_WEAK_LINKAGE,
    GHOST_LINKAGE,
    COMMON_LINKAGE,
    LINKER_PRIVATE_LINKAGE,
    LINKER_PRIVATE_WEAK_LINKAGE
}