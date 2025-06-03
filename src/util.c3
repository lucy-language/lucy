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

macro array_insert($Type, arr, element)
{
    $Type[] new_arr = mem::new_array($Type, arr.len + 1);
    
    for (int i = 0; i < arr.len; i++)
    {
        new_arr[i] = arr[i];
    }

    new_arr[arr.len] = element;

    return new_arr;
}
