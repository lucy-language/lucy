module lucy::attributes;

import lucy::node;

fn void inspect_call(String attr_name, CallNode call_node, String path)
{
    if (attr_name = "@variatric")
    {
        ASTNode*[] args = call_node.arguments;
    }
}
