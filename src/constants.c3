module lucy;

const VERSION_NUMBER  = "0.1.0";
const IS_PRE_RELEASE  = true;

const VERSION         = VERSION_NUMBER +++ (IS_PRE_RELEASE ? " (Pre-release)" : "");
const BACKENDS        = "LLVM";
