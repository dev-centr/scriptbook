module scriptbook.model;

/// One runnable step extracted from a CentrMark playbook profile.
struct Step
{
	string id;
	string cwd = ".";
	string shell = "auto"; // auto|nu|sh|bash|pwsh
	string timeout = "";
	string env = "";
	bool confirm = false;
	string when = ""; // e.g. prior-step success: "dns-check"
	string language; // fenced code language
	string script;
	int sourceLine; // 1-based open fence line, for diagnostics
}

struct Playbook
{
	string id;
	string shell = "auto"; // default for steps
	Step[] steps;
	string sourcePath;
}
