module scriptbook.model;

/// Nested option under ::: choose
struct Option
{
	string id;
	string whenContext;
	string formats;
}

/// One runnable item extracted from a CentrMark playbook profile.
struct Step
{
	string kind = "step"; // step | choose | ask
	string id;
	string cwd = ".";
	string shell = "auto"; // auto|nu|sh|bash|pwsh — glue cells only
	string timeout = "";
	string env = "";
	bool confirm = false;
	string when = ""; // prior-step success
	string whenAnswer = ""; // key=value
	string whenContext = ""; // windows/* or a context id
	string language; // fenced code language
	string script;
	int sourceLine; // 1-based open fence line, for diagnostics

	string intent; // e.g. cli.install
	string tool;
	string bind; // choose id whose answer is the format
	string prompt;
	Option[] options;

	// Filled at play time (not authored)
	string resolvedCommand;
	string[] argv;
	string format;
	string context;
	string runtime;
}

struct Playbook
{
	string id;
	string shell = "auto"; // default for glue steps
	Step[] steps;
	string sourcePath;
}
