# Lucy Compiler

> [!CAUTION]
> Unfinished project

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

## Supported systems
| Name       | Tested                                                             |
|------------|--------------------------------------------------------------------|
| aarch64    | ![False](https://img.shields.io/badge/false-red?style=flat-square) |
| aarch64_be | ![False](https://img.shields.io/badge/false-red?style=flat-square) |
| aarch64_32 | ![False](https://img.shields.io/badge/false-red?style=flat-square) |
| arm        | ![False](https://img.shields.io/badge/false-red?style=flat-square) |
| armb       | ![False](https://img.shields.io/badge/false-red?style=flat-square) |
| thumb      | ![False](https://img.shields.io/badge/false-red?style=flat-square) |
| thumbeb    | ![False](https://img.shields.io/badge/false-red?style=flat-square) |
| riscv32    | ![False](https://img.shields.io/badge/false-red?style=flat-square) |
| riscv64    | ![False](https://img.shields.io/badge/false-red?style=flat-square) |
| x86        | ![False](https://img.shields.io/badge/false-red?style=flat-square) |
| x86_64     | ![True](https://img.shields.io/badge/true-green?style=flat-square) |
| xcore      | ![False](https://img.shields.io/badge/false-red?style=flat-square) |

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