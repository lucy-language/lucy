module llvm;

extern fn LLVMModuleRef module_create_with_name(char* module_id) @extern("LLVMModuleCreateWithName");
extern fn void module_dispose(LLVMModuleRef m) @extern("LLVMModuleDispose");
extern fn void dump_module(LLVMModuleRef m) @extern("LLVMDumpModule");
extern fn LLVMContextRef context_create() @extern("LLVMContextCreate");
extern fn void context_dispose(LLVMContextRef c) @extern("LLVMContextDispose");
extern fn LLVMValueRef add_function(LLVMModuleRef m, char* name, LLVMTypeRef ty) @extern("LLVMAddFunction");
extern fn LLVMValueRef get_named_function(LLVMModuleRef m, char* name) @extern("LLVMGetNamedFunction");
extern fn LLVMBasicBlockRef append_basic_block(LLVMValueRef fN, char* name) @extern("LLVMAppendBasicBlock");
extern fn LLVMBasicBlockRef get_insert_block(LLVMBuilderRef builder) @extern("LLVMGetInsertBlock");
extern fn void position_builder(LLVMBuilderRef builder, LLVMBasicBlockRef block, LLVMValueRef instr) @extern("LLVMPositionBuilder");
extern fn void position_builder_at_end(LLVMBuilderRef builder, LLVMBasicBlockRef block) @extern("LLVMPositionBuilderAtEnd");
extern fn LLVMBuilderRef create_builder() @extern("LLVMCreateBuilder");
extern fn void dispose_builder(LLVMBuilderRef builder) @extern("LLVMDisposeBuilder");
extern fn int link_in_mcjit() @extern("LLVMLinkInMCJIT");
extern fn int link_in_interpreter() @extern("LLVMLinkInInterpreter");
extern fn int create_execution_engine_for_module(LLVMExecutionEngineRef* ee, LLVMModuleRef m, char** error) @extern("LLVMCreateExecutionEngineForModule");
extern fn int run_function(LLVMExecutionEngineRef ee, LLVMValueRef f, usz num_args, LLVMGenericValueRef* args) @extern("LLVMRunFunction");
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
extern fn LLVMContextRef get_global_context() @extern("LLVMGetGlobalContext");

extern fn LLVMTypeRef int1_type() @extern("LLVMInt1Type");
extern fn LLVMTypeRef int8_type() @extern("LLVMInt8Type");
extern fn LLVMTypeRef int32_type() @extern("LLVMInt32Type");
extern fn LLVMTypeRef int64_type() @extern("LLVMInt64Type");
extern fn LLVMTypeRef float_type() @extern("LLVMFloatType");
extern fn LLVMTypeRef double_type() @extern("LLVMDoubleType");
extern fn LLVMTypeRef void_type() @extern("LLVMVoidType");
extern fn LLVMTypeRef pointer_type(LLVMTypeRef element_type, CUInt address_space) @extern("LLVMPointerType");
extern fn LLVMTypeRef function_type(LLVMTypeRef return_type, LLVMTypeRef* param_types, usz param_count, int is_var_arg) @extern("LLVMFunctionType");
extern fn LLVMTypeRef struct_type(LLVMTypeRef* types, CUInt size, LLVMBool packed) @extern("LLVMStructType");
extern fn LLVMTypeRef array_type(LLVMTypeRef type, CUInt size) @extern("LLVMArrayType");

extern fn LLVMValueRef const_int(LLVMTypeRef ty, ulong n, int sign_extend) @extern("LLVMConstInt");
extern fn LLVMValueRef const_real(LLVMTypeRef ty, double n) @extern("LLVMConstReal");
extern fn LLVMValueRef const_string(char* str, usz len, LLVMBool dont_null_terminate) @extern("LLVMConstString");
extern fn LLVMValueRef const_struct(LLVMValueRef * constant_vals, usz count, int packed) @extern("LLVMConstStruct");
extern fn LLVMValueRef const_string_in_context(LLVMContextRef context, char* str, usz len, LLVMBool dont_null_terminate) @extern("LLVMConstString");
extern fn LLVMValueRef const_bit_cast(LLVMValueRef value, LLVMTypeRef type) @extern("LLVMConstBitCast");

extern fn LLVMValueRef build_call_2(LLVMBuilderRef builder, LLVMTypeRef fn_type, LLVMValueRef fN, LLVMValueRef* args, CUInt size, char* name) @extern("LLVMBuildCall2");
extern fn LLVMValueRef build_extract_value(LLVMBuilderRef builder, LLVMValueRef val, CUInt index, char* name) @extern("LLVMBuildExtractValue");
extern fn LLVMValueRef build_alloca(LLVMBuilderRef builder, LLVMTypeRef type, char* name) @extern("LLVMBuildAlloca");
extern fn LLVMValueRef build_ret_void(LLVMBuilderRef builder) @extern("LLVMBuildRetVoid");
extern fn LLVMValueRef build_ret(LLVMBuilderRef builder, LLVMValueRef v) @extern("LLVMBuildRet");
extern fn LLVMValueRef build_f_add(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, char* name) @extern("LLVMBuildFAdd");
extern fn LLVMValueRef build_f_sub(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, char* name) @extern("LLVMBuildFSub");
extern fn LLVMValueRef build_f_mul(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, char* name) @extern("LLVMBuildFMul");
extern fn LLVMValueRef build_f_div(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, char* name) @extern("LLVMBuildFDiv");
extern fn LLVMValueRef build_add(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, char* name) @extern("LLVMBuildAdd");
extern fn LLVMValueRef build_sub(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, char* name) @extern("LLVMBuildSub");
extern fn LLVMValueRef build_mul(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, char* name) @extern("LLVMBuildMul");
extern fn LLVMValueRef build_s_div(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, char* name) @extern("LLVMBuildSDiv");
extern fn LLVMValueRef build_load(LLVMBuilderRef builder, LLVMValueRef val, char* name) @extern("LLVMBuildLoad2");
extern fn LLVMValueRef build_load_2(LLVMBuilderRef builder, LLVMTypeRef type, LLVMValueRef val, char* name) @extern("LLVMBuildLoad2");
extern fn LLVMValueRef build_br(LLVMBuilderRef builder, LLVMBasicBlockRef dest) @extern("LLVMBuildBr");
extern fn LLVMValueRef build_cond_br(LLVMBuilderRef builder, LLVMValueRef condition, LLVMBasicBlockRef then_block, LLVMBasicBlockRef else_block) @extern("LLVMBuildCondBr");
extern fn LLVMValueRef build_i_cmp(LLVMBuilderRef builder, LLVMIntPredicate operation, LLVMValueRef lhs, LLVMValueRef rhs, char* name) @extern("LLVMBuildICmp");
extern fn LLVMValueRef build_f_cmp(LLVMBuilderRef builder, LLVMIntPredicate operation, LLVMValueRef lhs, LLVMValueRef rhs, char* name) @extern("LLVMBuildFCmp");
extern fn void         build_store(LLVMBuilderRef builder, LLVMValueRef val, LLVMValueRef variable) @extern("LLVMBuildStore");
extern fn LLVMValueRef build_gep(LLVMBuilderRef builder, LLVMValueRef pointer, LLVMValueRef* indices, CUInt num_indices, char* name) @extern("LLVMBuildGEP");
extern fn LLVMValueRef build_gep_2(LLVMBuilderRef builder, LLVMTypeRef type, LLVMValueRef pointer, LLVMValueRef* indices, CUInt num_indices, char* name) @extern("LLVMBuildGEP2");
extern fn LLVMValueRef build_struct_gep_2(LLVMBuilderRef builder, LLVMTypeRef type, LLVMValueRef pointer, CUInt index, char* name) @extern("LLVMBuildStructGEP2");
extern fn LLVMValueRef build_phi(LLVMBuilderRef builder, LLVMTypeRef type, char* name) @extern("LLVMBuildPhi");

extern fn LLVMTypeKind get_type_kind(LLVMTypeRef type) @extern("LLVMGetTypeKind");
extern fn LLVMValueRef get_operand(LLVMValueRef val, CUInt index) @extern("LLVMGetOperand");
extern fn void         get_struct_element_types(LLVMTypeRef type, LLVMTypeRef* dest) @extern("LLVMGetStructElementTypes");
extern fn LLVMTypeRef  get_struct_element_type(LLVMTypeRef type, CInt index) @extern("LLVMGetStructElementTypes");
extern fn usz          get_num_operands(LLVMValueRef val) @extern("LLVMGetNumOperands");
extern fn LLVMTypeRef  get_element_type(LLVMTypeRef type) @extern("LLVMGetElementType");
extern fn String       get_struct_element_name(LLVMTypeRef type, CUInt index) @extern("LLVMGetStructElementName");
extern fn String       get_struct_name(LLVMTypeRef type) @extern("LLVMGetStructName");
extern fn CInt         get_struct_field_index(LLVMTypeRef type, char* name) @extern("LLVMGetStructFieldIndex");
extern fn LLVMTypeRef  get_type_by_name(LLVMModuleRef mod, char* name) @extern("LLVMGetTypeByName");
extern fn char*        get_value_name(LLVMValueRef value) @extern("LLVMGetValueName");
extern fn LLVMValueRef get_initializer(LLVMValueRef value) @extern("LLVMGetInitializer");
extern fn char*        get_as_string(LLVMValueRef initializer, CInt* len) @extern("LLVMGetAsString");

extern fn CUInt count_struct_element_types(LLVMTypeRef type) @extern("LLVMCountStructElementTypes");

extern fn LLVMBasicBlockRef create_basic_block_in_context(LLVMContextRef ctx, char* name) @extern("LLVMCreateBasicBlockInContext");

extern fn void add_incoming(LLVMValueRef phi_node, LLVMValueRef* incoming_values, LLVMBasicBlockRef* incoming_blocks, CUInt count) @extern("LLVMAddIncoming");

extern fn LLVMTypeRef struct_create_named(LLVMContextRef context, char* name) @extern("LLVMStructCreateNamed");
extern fn void        struct_set_body(LLVMTypeRef type, LLVMTypeRef* types, CUInt types_count, LLVMBool is_packed) @extern("LLVMStructSetBody");
extern fn LLVMTypeRef struct_get_type_at_index(LLVMTypeRef type, CUInt index) @extern("LLVMStructGetTypeAtIndex");

extern fn LLVMBool is_struct_type(LLVMTypeRef type) @extern("LLVMIsStructType");

extern fn char* print_value_to_string(LLVMValueRef value) @extern("LLVMPrintValueToString");
extern fn char* print_type_to_string(LLVMTypeRef value) @extern("LLVMPrintTypeToString");

extern fn bool is_a_global_variable(LLVMValueRef variable) @extern("LLVMIsAGlobalVariable");
extern fn bool is_constant(LLVMValueRef variable) @extern("LLVMIsConstant");
extern fn bool is_a_constant_data_array(LLVMValueRef variable) @extern("LLVMIsAConstantDataArray");
extern fn bool is_a_load_inst(LLVMValueRef variable) @extern("LLVMIsLoadInst");
extern fn bool is_a_get_element_ptr_inst(LLVMValueRef variable) @extern("LLVMIsAGetElementPtrInst");

const TRUE  = 1;
const FALSE = 0;

alias LLVMBool                     = CInt;
alias LLVMContextRef               = void*;
alias LLVMModuleRef                = void*;
alias LLVMTypeRef                  = void*;
alias LLVMValueRef                 = void*;
alias LLVMBasicBlockRef            = void*;
alias LLVMBuilderRef               = void*;
alias LLVMPassManagerRef           = void*;
alias LLVMPassRegistryRef          = void*;
alias LLVMMemoryBufferRef          = void*;
alias LLVMOpaquePassManagerBuilder = void*;
alias LLVMPassManagerBuilderRef    = LLVMOpaquePassManagerBuilder*;
alias LLVMExecutionEngineRef       = void*;
alias LLVMTargetDataRef            = void*;
alias LLVMTargetMachineRef         = void*;
alias LLVMTargetRef                = void*;
alias LLVMTargetLibraryInfoRef     = void*;
alias LLVMGenericValueRef          = void*;
alias LLVMMCJITMemoryManagerRef    = void*;
alias LLVMOpcode                   = CUInt;
alias LLVMDiagnosticInfoRef        = void*;
alias LLVMComdatRef                = void*;
alias LLVMMetadataRef              = void*;
alias LLVMNamedMDNodeRef           = void*;
alias LLVMValueMetadataEntry       = void*;
alias LLVMInlineAsmDialect         = CUInt;
alias LLVMAttributeRef             = void*;
alias LLVMIntPredicate             = int;
alias LLVMRealPredicate            = int;
alias LLVMGlobalVariableRef        = void*;

enum LLVMTypeKind
{
    VOID_TYPE_KIND,
    HALF_TYPE_KIND,
    FLOAT_TYPE_KIND,
    DOUBLE_TYPE_KIND,
    X86_FP80_TYPE_KIND,
    FP128_TYPE_KIND,
    PPC_FP128_TYPE_KIND,
    LABEL_TYPE_KIND,
    INTEGER_TYPE_KIND,
    FUNCTION_TYPE_KIND,
    STRUCT_TYPE_KIND,
    ARRAY_TYPE_KIND,
    POINTER_TYPE_KIND,
    VECTOR_TYPE_KIND,
    METADATA_TYPE_KIND,
    X86_MMX_TYPE_KIND,
    TOKEN_TYPE_KIND,
    SCALABLE_VECTOR_TYPE_KIND,
    TARGET_EXT_TYPE_KIND
}

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

const LLVMIntPredicate INT_EQ  = 32;
const LLVMIntPredicate INT_NE  = 33;
const LLVMIntPredicate INT_UGT = 34;
const LLVMIntPredicate INT_UGE = 35;
const LLVMIntPredicate INT_ULT = 36;
const LLVMIntPredicate INT_ULE = 37;
const LLVMIntPredicate INT_SGT = 38;
const LLVMIntPredicate INT_SGE = 39;
const LLVMIntPredicate INT_SLT = 40;
const LLVMIntPredicate INT_SLE = 41;

const LLVMRealPredicate REAL_PREDICATE_FALSE = 0;
const LLVMRealPredicate REAL_OEQ             = 1;
const LLVMRealPredicate REAL_OGT             = 2;
const LLVMRealPredicate REAL_OGE             = 3;
const LLVMRealPredicate REAL_OLT             = 4;
const LLVMRealPredicate REAL_OLE             = 5;
const LLVMRealPredicate REAL_ONE             = 6;
const LLVMRealPredicate REAL_ORD             = 7;
const LLVMRealPredicate REAL_UNO             = 8;
const LLVMRealPredicate REAL_UEQ             = 9;
const LLVMRealPredicate REAL_UGT             = 10;
const LLVMRealPredicate REAL_UGE             = 11;
const LLVMRealPredicate REAL_ULT             = 12;
const LLVMRealPredicate REAL_ULE             = 13;
const LLVMRealPredicate REAL_UNE             = 14;
const LLVMRealPredicate REAL_PREDICATE_TRUE  = 15;
