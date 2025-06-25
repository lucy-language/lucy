module lucy::lookup_table;

import std::io;
import llvm;

extern fn CInt strcmp(char* s1, char* s2);

const int TABLE_SIZE               = 256;
const int BUILTIN_TYPE_FIELD_COUNT = 5; // $typeid, $typekind, $typename, $size, $numfields

struct Field
{
    char* name;
    Type* type;
}

struct Type
{
    char*       name;
    Field*      fields;
    int         num_fields;
    LLVMTypeRef llvm_type;
    int         type_id;
}

struct TypeEntry
{
    char*      key;
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
    
    (*entry).key          = (*type).name;
    (*entry).value        = type;
    (*entry).next         = (*self).entries[slot];
    (*self).entries[slot] = entry;
}

fn Type* TypeTable.lookup(&self, char* name)
{
    uint slot = hash(name);
    TypeEntry* entry = (*self).entries[slot];
    while (entry != null)
    {
        if (strcmp((*entry).key, name) == 0)
        {
            return (entry).value;
        }
        entry = (*entry).next;
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

    self.insert_type("int",    null, llvm::int32_type());
    self.insert_type("float",  null, llvm::float_type());
    self.insert_type("str",    null, llvm::pointer_type(llvm::int8_type(), 0));
    self.insert_type("bool",   null, llvm::int1_type());
    self.insert_type("char",   null, llvm::int8_type());
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
    int num_fields = 4;

    Field* fields  = malloc(Field.sizeof * num_fields);
    ((Field[])fields[:num_fields])[0] = { "$typeid",   self.lookup("int") };
    ((Field[])fields[:num_fields])[1] = { "$typekind", self.lookup("str") };
    ((Field[])fields[:num_fields])[2] = { "$typename", self.lookup("str") };
    ((Field[])fields[:num_fields])[3] = { "$size",     self.lookup("int") };

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

fn void TypeTable.insert_type(&self, char* name, Field* fields, LLVMTypeRef llvm_type) @private
{
    Type* type = malloc(Type.sizeof);
    (*type).name      = name;
    (*type).fields    = fields;
    (*type).llvm_type = llvm_type;
    (*type).type_id   = self.type_id++;

    self.insert(type);
}

fn Type* Type.get_field_type(&self, char* field_name)
{
    if (!self || !(*self).fields) return null;
    for (Field* f = (*self).fields; (*f).name != null; f++)
    {
        if (strcmp((*f).name, field_name) == 0)
        {
            return (*f).type;
        }
    }
    return null;
}

fn Field* Type.get_field(&self, char* field_name)
{
    if (!self || !(*self).fields) return null;
    
    for (Field* f = (*self).fields; (*f).name != null; f++)
    {
        if (strcmp((*f).name, field_name) == 0) // strcmp errors???
        {
            return f;
        }
    }
    return null;
}

fn bool TypeTable.has(&self, char* name)
{
    uint slot = hash(name);
    TypeEntry* entry = (*self).entries[slot];
    while (entry != null)
    {
        if (strcmp((*entry).key, name) == 0)
        {
            return true;
        }
        entry = (*entry).next;
    }

    return false;
}
