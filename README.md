# Lucy Compiler

# ⚠️ DISCLAIMER ⚠️

### this project is unfinished

## Description

This is a compiler written in [C3](https://c3-lang.org/).

## Key features
- #### in-file linker options*
- #### package- or module-like structure
- #### simple syntax

*for more readability and less guessing. the compiler automatically links with everything specified in the files to remove need to figure out what to link with and manually link it

## Code Example

```
pkg main;

ext void printf(str fmt, var str args);

struct Person
{
    Name name;
    int  age;
}

struct Name
{
    str first_name;
    str last_name;
}

def void main() 
{
    var Person p =
    {
        {
            "Kiana",
            "Bennett"
        },
        22
    };
    printf("Hello, %s!", p.name.first_name);
}
```

## Building and Running

### Prerequisites
- C3 compiler installed (available from [c3-lang.org](https://c3-lang.org/))
- libLLVM (available from [releases.llvm.org](https://releases.llvm.org/download.html))

### Building the Compiler

```bash
c3c build -l LLVM
```

### Using the Compiler

```bash
./build/lucy compile <file_name.lc>
./<file_name>

# Show help message
./build/lucy --help
```

you don't have to specify linked libraries like this, it's fully optional but recommended for readability and simplicity. you can remove the link options at the top of the file and run this instead
```bash
lucy compile main.lc -lraylib
```

## Contributing

Contributions are welcome! Please submit pull requests or open issues for any bugs or feature requests.

## [License](LICENSE)