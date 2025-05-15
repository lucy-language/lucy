module lucy::util;

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