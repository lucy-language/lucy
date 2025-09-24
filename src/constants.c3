module lucy;

const VERSION_NUMBER  = "0.1.0";
const IS_PRE_RELEASE  = true;

const VERSION         = VERSION_NUMBER +++ (IS_PRE_RELEASE ? " (Pre-release)" : "");
const BACKENDS        = "LLVM, MLIR, LUCY, QBE";

// GIT_HASH
$exec(`echo "const GIT_HASH = \"$(git rev-parse HEAD)\";"`);
