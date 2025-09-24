module lucy::types;

import llvm;

const int TABLE_SIZE               = 256;
const int BUILTIN_TYPE_FIELD_COUNT = 5; // $typeid, $typekind, $typename, $size, $numfields

struct Field
{
    ZString name;
    Type*   type;
}

struct Type
{
    ZString     name;
    Field*      fields;
    int         num_fields;
    LLVMTypeRef llvm_type;
    int         type_id;
    bool        is_array;
    bool        is_pointer;
}

struct TypeEntry
{
    ZString    key;
    Type*      value;
    TypeEntry* next;
}

struct TypeTable
{
    TypeEntry*[TABLE_SIZE] entries;
    int                    type_id;
}

fn uint hash(char* str) @private
{
    ulong hash = 5381;
    int c;
    while ((c = *str++))
    {
        hash = ((hash << 5) + hash) + c;
    }
    return (uint)(hash % TABLE_SIZE);
}

fn void TypeTable.insert(&self, Type* type)
{
    uint slot = hash((*type).name);
    TypeEntry* entry = malloc(TypeEntry.sizeof);
    
    (*entry).key           = type.name;
    (*entry).value         = type;
    (*entry).next          = self.entries[slot];
    (*self) .entries[slot] = entry;
}

fn Type* TypeTable.lookup(&self, String name_in)
{
    ZString name = name_in.zstr_copy(mem);
    uint slot = hash(name);
    TypeEntry* entry = self.entries[slot];
    while (entry != null)
    {
        if (entry.key == name)
        {
            return entry.value;
        }
        entry = entry.next;
    }

    return null;
}

fn void TypeTable.init(&self, int type_id = 0)
{
    for (int i = 0; i < TABLE_SIZE; i++)
    {
        self.entries[i] = null;
    }
    self.type_id = type_id;

    LLVMTypeRef int_type = (void*).sizeof == 8 ? llvm::int_64_type() : llvm::int_32_type();

    self.insert_type("void",   null, llvm::void_type());
    self.insert_type("int",    null, int_type);
    self.insert_type("float",  null, llvm::float_type());
    self.insert_type("str",    null, llvm::pointer_type(llvm::int_8_type(), 0));
    self.insert_type("bool",   null, llvm::int_1_type());
    self.insert_type("char",   null, llvm::int_8_type());
    self.insert_type("double", null, llvm::double_type());

    self.init_builtin_fields();
}

fn void TypeTable.init_builtin_fields(&self)
{
    self.init_int_type();
    self.init_float_type();
    self.init_str_type();
    self.init_bool_type();
    self.init_char_type();
    self.init_double_type();
}

fn void TypeTable.init_int_type(&self)
{
    int num_fields = 4;

    Field* fields  = malloc(Field.sizeof * num_fields);
    ((Field[])fields[:num_fields])[0] = { "$typeid",   self.lookup("int") };
    ((Field[])fields[:num_fields])[1] = { "$typekind", self.lookup("str") };
    ((Field[])fields[:num_fields])[2] = { "$typename", self.lookup("str") };
    ((Field[])fields[:num_fields])[3] = { "$size",     self.lookup("int") };

    Type* type = self.lookup("int");
    (*type).fields = fields;
}

fn void TypeTable.init_float_type(&self)
{
    int num_fields = 4;

    Field* fields  = malloc(Field.sizeof * num_fields);
    ((Field[])fields[:num_fields])[0] = { "$typeid",   self.lookup("int") };
    ((Field[])fields[:num_fields])[1] = { "$typekind", self.lookup("str") };
    ((Field[])fields[:num_fields])[2] = { "$typename", self.lookup("str") };
    ((Field[])fields[:num_fields])[3] = { "$size",     self.lookup("int") };

    Type* type = self.lookup("float");
    (*type).fields = fields;
}

fn void TypeTable.init_str_type(&self)
{
    int num_fields = 5;

    Field* fields  = malloc(Field.sizeof * num_fields);
    ((Field[])fields[:num_fields])[0] = { "$typeid",   self.lookup("int") };
    ((Field[])fields[:num_fields])[1] = { "$typekind", self.lookup("str") };
    ((Field[])fields[:num_fields])[2] = { "$typename", self.lookup("str") };
    ((Field[])fields[:num_fields])[3] = { "$size",     self.lookup("int") };
    ((Field[])fields[:num_fields])[4] = { "$length",   self.lookup("int") };

    Type* type = self.lookup("str");
    (*type).fields = fields;
}

fn void TypeTable.init_bool_type(&self)
{
    int num_fields = 4;

    Field* fields  = malloc(Field.sizeof * num_fields);
    ((Field[])fields[:num_fields])[0] = { "$typeid",   self.lookup("int") };
    ((Field[])fields[:num_fields])[1] = { "$typekind", self.lookup("str") };
    ((Field[])fields[:num_fields])[2] = { "$typename", self.lookup("str") };
    ((Field[])fields[:num_fields])[3] = { "$size",     self.lookup("int") };

    Type* type = self.lookup("bool");
    (*type).fields = fields;
}

fn void TypeTable.init_char_type(&self)
{
    int num_fields = 4;

    Field* fields  = malloc(Field.sizeof * num_fields);
    ((Field[])fields[:num_fields])[0] = { "$typeid",   self.lookup("int") };
    ((Field[])fields[:num_fields])[1] = { "$typekind", self.lookup("str") };
    ((Field[])fields[:num_fields])[2] = { "$typename", self.lookup("str") };
    ((Field[])fields[:num_fields])[3] = { "$size",     self.lookup("int") };

    Type* type = self.lookup("char");
    (*type).fields = fields;
}

fn void TypeTable.init_double_type(&self)
{
    int num_fields = 4;

    Field* fields  = malloc(Field.sizeof * num_fields);
    ((Field[])fields[:num_fields])[0] = { "$typeid",   self.lookup("int") };
    ((Field[])fields[:num_fields])[1] = { "$typekind", self.lookup("str") };
    ((Field[])fields[:num_fields])[2] = { "$typename", self.lookup("str") };
    ((Field[])fields[:num_fields])[3] = { "$size",     self.lookup("int") };

    Type* type = self.lookup("double");
    (*type).fields = fields;
}

fn void TypeTable.insert_type(&self, String name_in, Field* fields, LLVMTypeRef llvm_type, bool is_array = false, bool is_pointer = false)
{
    ZString name = name_in.zstr_copy(mem);
    Type* type = malloc(Type.sizeof);
    (*type).name      = name;
    (*type).fields    = fields;
    (*type).llvm_type = llvm_type;
    (*type).type_id   = self.type_id++;

    self.insert(type);
}

fn Type* Type.get_field_type(&self, String field_name_in)
{
    ZString field_name = field_name_in.zstr_copy(mem);
    if (!self || !self.fields) return null;
    for (Field* f = self.fields; f.name != null; f++)
    {
        if (f.name == field_name)
        {
            return f.type;
        }
    }
    return null;
}

fn Field* Type.get_field(&self, String field_name_in)
{
    ZString field_name = field_name_in.zstr_copy(mem);
    if (!self || !self.fields) return null;
    
    for (Field* f = self.fields; f.name != null; f++)
    {
        if (f.name == field_name)
        {
            return f;
        }
    }
    return null;
}

fn bool TypeTable.has(&self, String name_in)
{
    ZString name = name_in.zstr_copy(mem);
    uint slot = hash(name);
    TypeEntry* entry = self.entries[slot];
    while (entry != null)
    {
        if (entry.key == name)
        {
            return true;
        }
        entry = entry.next;
    }

    return false;
}

fn void TypeTable.append_builtin_type_fields(&self, Field* fields, int offset)
{
    // typeid, typekind, typename, size, numfields
    ((Field[])fields[:offset + BUILTIN_TYPE_FIELD_COUNT])[offset + 0].name = "$typeid";
    ((Field[])fields[:offset + BUILTIN_TYPE_FIELD_COUNT])[offset + 0].type = self.lookup("int");

    ((Field[])fields[:offset + BUILTIN_TYPE_FIELD_COUNT])[offset + 1].name = "$typekind";
    ((Field[])fields[:offset + BUILTIN_TYPE_FIELD_COUNT])[offset + 1].type = self.lookup("str");

    ((Field[])fields[:offset + BUILTIN_TYPE_FIELD_COUNT])[offset + 2].name = "$typename";
    ((Field[])fields[:offset + BUILTIN_TYPE_FIELD_COUNT])[offset + 2].type = self.lookup("str");

    ((Field[])fields[:offset + BUILTIN_TYPE_FIELD_COUNT])[offset + 3].name = "$size";
    ((Field[])fields[:offset + BUILTIN_TYPE_FIELD_COUNT])[offset + 3].type = self.lookup("int");

    ((Field[])fields[:offset + BUILTIN_TYPE_FIELD_COUNT])[offset + 4].name = "$numfields";
    ((Field[])fields[:offset + BUILTIN_TYPE_FIELD_COUNT])[offset + 4].type = self.lookup("int");
}
