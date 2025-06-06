module lucy::util;

import lucy;
import std;

const String LOWERCASE   = "abcdefghijklmnopqrstuvwxyz";
const String UPPERCASE   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

fn bool char.in(self, char[] arr)
{
    foreach (i : arr)
    {
        if (i == self) return true;
    }

    return false;
}

fn bool String.in(self, String[] arr)
{
    foreach (i : arr)
    {
        if (i == self) return true;
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
