module argparser;

import color_util;
import std::io;
import std::os;

const int EXIT_SUCCESS = 0;
const int EXIT_FAILURE = 1;

struct Option
{
    char   short_name;
    String long_name;
    String description;
    bool   has_arg;
    bool   required;
    String value;
    bool   subcommand;
}

struct ArgParser
{
    String[] args;
    Option[] options;
}

fn String ArgParser.get_arg(&self, String name)
{
    for (int i = 0; i < self.options.len; i++)
    {
        if (name == self.options[i].long_name || (name.len == 1 && name[0] == self.options[i].short_name))
        {
            return self.options[i].value;
        }
    }

    io::eprintfn("%sArgument '%s' is not defined%s", color_util::COLOR_RED, name, color_util::COLOR_RESET);
    os::exit(EXIT_FAILURE);
}

fn bool ArgParser.has_arg(&self, String name)
{
    for (int i = 0; i < self.options.len; i++)
    {
        if (name == self.options[i].long_name || (name.len == 1 && name[0] == self.options[i].short_name))
        {
            return self.options[i].value != "";
        }
    }
    return false;
}

fn void ArgParser.parse(&self)
{
    for (int i = 1; i < self.args.len; i++)
    {
        String arg = self.args[i];

        if (arg == "--help" || arg == "-h")
        {
            self.print_usage();
            os::exit(EXIT_SUCCESS);
        }

        // TODO: add checking for missing value
        foreach (j, option : self.options)
        {
            if (option.subcommand && option.long_name == arg)
            {
                self.options[j].value = self.args[i + 1];
            }
        }

        for (int j = 0; j < self.options.len; j++)
        {
            bool is_long = arg.starts_with("--") && arg[2..] == self.options[j].long_name;
            bool is_short = arg.starts_with("-") && !arg.starts_with("--") &&  arg[1] == self.options[j].short_name && arg.len == 2;

            if (is_long || is_short)
            {
                if (self.options[j].has_arg)
                {
                    if (i + 1 >= self.args.len)
                    {
                        io::eprintfn("%sOption '%s' requires an argument%s", color_util::COLOR_RED, arg, color_util::COLOR_RESET);
                        os::exit(EXIT_FAILURE);
                    }
                    self.options[j].value = self.args[i + 1];
                    i++;
                } else
                {
                    self.options[j].value = arg;
                }
                break;
            }
        }
    }

    for (int i = 0; i < self.options.len; i++)
    {
        if (self.options[i].required && self.options[i].value == "")
        {
            io::eprintfn("%sOption '--%s' is required%s", color_util::COLOR_RED, self.options[i].long_name, color_util::COLOR_RESET);
            os::exit(EXIT_FAILURE);
        }
    }
}

fn void ArgParser.print_usage(&self)
{
    io::printfn("Usage: %s [<SUBCOMMAND>] [OPTIONS]", self.args[0]);
    io::printn();
    io::printn("Subcommands:");

    int max_long_name_len = 0;
    for (int i = 0; i < self.options.len; i++)
    {
        int len = self.options[i].long_name.len;
        if (len > max_long_name_len)
        {
            max_long_name_len = len;
        }
    }

    int max_subcommand_len = 0;
    for (int i = 0; i < self.options.len; i++)
    {
        if (self.options[i].subcommand)
        {
            int len = self.options[i].long_name.len;
            if (len > max_subcommand_len)
            {
                max_subcommand_len = len;
            }
        }
    }

    foreach (option : self.options)
    {
        if (option.subcommand)
        {
            io::printfn("  %-10s  %s", option.long_name, option.description);
        }
    }
    
    io::printn();
    io::printn("Options:");
    
    Option help_option = { .short_name = 'h', .long_name = "help", .description = "Displays this message",  .has_arg = false };

    if (help_option.short_name)
    {
        io::printfn("  -%c, --%-10s  %s", help_option.short_name, help_option.long_name, help_option.description);
    } else
    {
        io::printfn("      --%-10s  %s", help_option.long_name, help_option.description);
    }

    for (int i = 0; i < self.options.len; i++)
    {
        if (!self.options[i].subcommand)
        {
            if (self.options[i].short_name)
            {
                io::printfn("  -%c, --%-10s  %s", self.options[i].short_name, self.options[i].long_name, self.options[i].description);
            } else
            {
                io::printfn("      --%-10s  %s", self.options[i].long_name, self.options[i].description);
            }
        }
    }
}
