module lucy::util;

import color_util;
import std;
import llvm;

const String LOWERCASE   = "abcdefghijklmnopqrstuvwxyz";
const String UPPERCASE   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

macro bool in(arr, el)
{
    foreach (a : arr)
    {
        if (a == el) return true;
    }
    return false;
}

macro void array_insert(arr, element)
{
    var $Type = $typeof(element);
    $Type[] tmp = mem::new_array($Type, (*arr).len + 1);
    
    // avoid mem::copy for 0 sized array
    for (int i = 0; i < (*arr).len; i++)
    {
        tmp[i] = (*arr)[i];
    }

    tmp[(*arr).len] = element;

    *arr = tmp;
}

macro void panicf(String fmt, args..., String file, int line) @noreturn
{
    panic(string::tformat(fmt, args), file, line);
}

<*
 @require message.len <= 73 : "message cannot be longer than 73 characters"
*>
fn void panic(String message, String file, int line) @noreturn
{
    io::eprint  (color_util::COLOR_YELLOW);
    io::eprintn ("╭──────────────────────────────────────────────────────────────────────────────────╮");
    io::eprintn ("│ ⚠️ Feature not implemented yet                                                   │");
    io::eprintfn("│ Issue: %-*s │", 73, message);
    io::eprintfn("│ In file: %-*s │", 71, string::tformat("%s (%d)", file, line));
    io::eprintn ("│                                                                                  │");
    io::eprintn ("│ Please create an issue on github at https://github.com/lucy-language/lucy/issues │");
    io::eprintn ("│ and include your compiler version you can get by running `lucy --version`        │");
    io::eprintn ("╰──────────────────────────────────────────────────────────────────────────────────╯");
    io::eprintn (color_util::COLOR_RESET);
    os::exit(1);
}
