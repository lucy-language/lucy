/*
  Copyright 2025 Kiana Bennett
  
  Permission is hereby granted, free of charge, to any person obtaining a copy of this software
  and associated documentation files (the “Software”), to deal in the Software without
  restriction, including without limitation the rights to use, copy, modify, merge, publish,
  distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
  Software is furnished to do so, subject to the following conditions:
  
  The above copyright notice and this permission notice shall be included in all copies or
  substantial portions of the Software.
  
  THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
  OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
  OTHER DEALINGS IN THE SOFTWARE.
*/

module color_util;

import std::core::string;

const String COLOR_RESET             = "\u001B[0m";
const String COLOR_BOLD              = "\u001B[1m";
const String COLOR_DIM               = "\u001B[2m";
const String COLOR_ITALIC            = "\u001B[3m";
const String COLOR_UNDERLINE         = "\u001B[4m";
const String COLOR_BLINK             = "\u001B[5m";
const String COLOR_BLINK_FAST        = "\u001B[6m";
const String COLOR_REVERSE           = "\u001B[7m";
const String COLOR_HIDDEN            = "\u001B[8m";
const String COLOR_STRIKETHROUGH     = "\u001B[9m";
const String COLOR_BLACK             = "\u001B[30m";
const String COLOR_RED               = "\u001B[31m";
const String COLOR_GREEN             = "\u001B[32m";
const String COLOR_YELLOW            = "\u001B[33m";
const String COLOR_BLUE              = "\u001B[34m";
const String COLOR_MAGENTA           = "\u001B[35m";
const String COLOR_CYAN              = "\u001B[36m";
const String COLOR_WHITE             = "\u001B[37m";
const String COLOR_DEFAULT           = "\u001B[39m";
const String COLOR_BRIGHT_BLACK      = "\u001B[90m";
const String COLOR_BRIGHT_RED        = "\u001B[91m";
const String COLOR_BRIGHT_GREEN      = "\u001B[92m";
const String COLOR_BRIGHT_YELLOW     = "\u001B[93m";
const String COLOR_BRIGHT_BLUE       = "\u001B[94m";
const String COLOR_BRIGHT_MAGENTA    = "\u001B[95m";
const String COLOR_BRIGHT_CYAN       = "\u001B[96m";
const String COLOR_BRIGHT_WHITE      = "\u001B[97m";
const String COLOR_BG_BLACK          = "\u001B[40m";
const String COLOR_BG_RED            = "\u001B[41m";
const String COLOR_BG_GREEN          = "\u001B[42m";
const String COLOR_BG_YELLOW         = "\u001B[43m";
const String COLOR_BG_BLUE           = "\u001B[44m";
const String COLOR_BG_MAGENTA        = "\u001B[45m";
const String COLOR_BG_CYAN           = "\u001B[46m";
const String COLOR_BG_WHITE          = "\u001B[47m";
const String COLOR_BG_DEFAULT        = "\u001B[49m";
const String COLOR_BG_BRIGHT_BLACK   = "\u001B[100m";
const String COLOR_BG_BRIGHT_RED     = "\u001B[101m";
const String COLOR_BG_BRIGHT_GREEN   = "\u001B[102m";
const String COLOR_BG_BRIGHT_YELLOW  = "\u001B[103m";
const String COLOR_BG_BRIGHT_BLUE    = "\u001B[104m";
const String COLOR_BG_BRIGHT_MAGENTA = "\u001B[105m";
const String COLOR_BG_BRIGHT_CYAN    = "\u001B[106m";
const String COLOR_BG_BRIGHT_WHITE   = "\u001B[107m";

<*
 8-bit color code

 @require index >= 0   : `index value cannot be smaller than 0`
 @require index <= 255 : `index value cannot be larger than 255`
 @return `the formatting char for the given background color`
*>
fn String color_8bit_fg(int index)
{
    return string::tformat("\u001B[38;5;%dm", index);
}

<*
 8-bit color code

 @require index >= 0   : `index value cannot be smaller than 0`
 @require index <= 255 : `index value cannot be larger than 255`
 @return `the formatting char for the given background color`
*>
fn String color_8bit_bg(int index)
{
    return string::tformat("\u001B[48;5;%dm", index);
}

<*
 24-bit color code

 @require r >= 0   : `red value cannot be smaller than 0`
 @require r <= 255 : `red value cannot be larger than 255`
 @require g >= 0   : `green value cannot be smaller than 0`
 @require g <= 255 : `green value cannot be larger than 255`
 @require b >= 0   : `blue value cannot be smaller than 0`
 @require b <= 255 : `blue value cannot be larger than 255`
 @return `the formatting char for the given fireground color`
*>
fn String color_24bit_fg(int r, int g, int b)
{
    return string::tformat("\u001B[38;2;%d;%d;%dm", r, g, b);
}

<*
 24-bit color code

 @require r >= 0   : `red value cannot be smaller than 0`
 @require r <= 255 : `red value cannot be larger than 255`
 @require g >= 0   : `green value cannot be smaller than 0`
 @require g <= 255 : `green value cannot be larger than 255`
 @require b >= 0   : `blue value cannot be smaller than 0`
 @require b <= 255 : `blue value cannot be larger than 255`
 @return `the formatting char for the given fireground color`
 @return `the formatting char for the given background color`
*>
fn String color_24bit_bg(int r, int g, int b)
{
    return string::tformat("\u001B[48;2;%d;%d;%dm", r, g, b);
}