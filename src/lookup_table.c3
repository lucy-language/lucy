module lucy::lookup_table;

import std::io;
import llvm;

extern fn CInt strcmp(char* s1, char* s2);

const int TABLE_SIZE = 10;

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

fn void TypeTable.init(&self)
{
    self.insert_type("int",    null, llvm::int32_type());
    self.insert_type("float",  null, llvm::float_type());
    self.insert_type("str",    null, llvm::pointer_type(llvm::int8_type(), 0));
    //TODO: self.add_str_type();
    self.insert_type("bool",   null, llvm::int1_type());
    self.insert_type("char",   null, llvm::int8_type());
    self.insert_type("double", null, llvm::double_type());
}

fn void TypeTable.add_str_type(&self)
{
    int num_fields = 2;
    Field* fields  = malloc(Field.sizeof * num_fields);
    ((Field[])fields[:num_fields])[0] = { "$len",  self.lookup("int")   };
    ((Field[])fields[:num_fields])[1] = { "$type", self.lookup("int") };
    self.insert_type("str", fields, llvm::pointer_type(llvm::int8_type(), 0));
}

fn void TypeTable.insert_type(&self, char* name, Field* fields, LLVMTypeRef llvm_type) @private
{
    Type* type = malloc(Type.sizeof);
    (*type).name      = name;
    (*type).fields    = fields;
    (*type).llvm_type = llvm_type;

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
        if (strcmp((*f).name, field_name) == 0)
        {
            return f;
        }
    }
    return null;
}
