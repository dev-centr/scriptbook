module scriptbook.parse;

import std.algorithm : startsWith;
import std.array : appender;
import std.conv : to;
import std.string : indexOf, splitLines, strip;

import scriptbook.model;
import scriptbook.props;

private struct OpenFence
{
	int len;
	string name;
	string propsRaw;
	int line; // 1-based
}

private bool parseDirectiveOpen(string line, ref OpenFence fence)
{
	auto s = line.strip;
	if (!s.startsWith(":"))
		return false;
	int n = 0;
	while (n < s.length && s[n] == ':')
		n++;
	if (n < 3)
		return false;
	auto rest = s[n .. $].strip;
	if (rest.length == 0)
		return false;

	string name;
	string props;
	auto bracket = rest.indexOf('[');
	if (bracket < 0)
	{
		name = rest.strip;
	}
	else
	{
		name = rest[0 .. bracket].strip;
		props = rest[bracket .. $].strip;
	}
	if (name.length == 0)
		return false;
	fence = OpenFence(n, name, props, 0);
	return true;
}

private bool isCloseFence(string line, int len)
{
	auto s = line.strip;
	if (s.length < len)
		return false;
	foreach (i; 0 .. len)
		if (s[i] != ':')
			return false;
	// exact fence of colons only (optional trailing whitespace already stripped)
	foreach (i; len .. s.length)
		if (s[i] != ':')
			return false;
	return true;
}

private void extractCodeFence(string body, ref string language, ref string code)
{
	language = "";
	code = body.strip;
	auto lines = body.splitLines;
	int open = -1;
	int fenceLen = 0;
	string lang;
	foreach (i, line; lines)
	{
		auto s = line.strip;
		if (!s.startsWith("`"))
			continue;
		int n = 0;
		while (n < s.length && s[n] == '`')
			n++;
		if (n < 3)
			continue;
		open = cast(int) i;
		fenceLen = n;
		lang = s[n .. $].strip;
		break;
	}
	if (open < 0)
		return;

	int close = -1;
	foreach (i; open + 1 .. lines.length)
	{
		auto s = lines[i].strip;
		int n = 0;
		while (n < s.length && s[n] == '`')
			n++;
		if (n >= fenceLen && s[n .. $].strip.length == 0)
		{
			close = cast(int) i;
			break;
		}
	}
	if (close < 0)
		return;

	language = lang;
	auto buf = appender!string();
	foreach (i; open + 1 .. close)
	{
		if (buf.data.length)
			buf.put('\n');
		buf.put(lines[i]);
	}
	code = buf.data;
}

private Step stepFromBody(string propsRaw, string body, int sourceLine, string defaultShell)
{
	auto props = parseProps(propsRaw);
	Step step;
	step.id = propGet(props, "id", "");
	step.cwd = propGet(props, "cwd", ".");
	step.shell = propGet(props, "shell", defaultShell);
	step.timeout = propGet(props, "timeout", "");
	step.env = propGet(props, "env", "");
	step.confirm = propBool(props, "confirm", false);
	step.when = propGet(props, "when", "");
	step.whenAnswer = propGet(props, "when-answer", "");
	step.whenContext = propGet(props, "when-context", "");
	step.intent = propGet(props, "intent", "");
	step.tool = propGet(props, "tool", "");
	step.bind = propGet(props, "bind", "");
	step.prompt = propGet(props, "prompt", "");
	step.sourceLine = sourceLine;
	extractCodeFence(body, step.language, step.script);
	if (step.id.length == 0)
		step.id = "step-" ~ to!string(sourceLine);
	return step;
}

private Option[] parseOptions(string body)
{
	Option[] opts;
	foreach (line; body.splitLines)
	{
		OpenFence open;
		if (!parseDirectiveOpen(line, open))
			continue;
		if (open.name != "option")
			continue;
		auto props = parseProps(open.propsRaw);
		Option o;
		o.id = propGet(props, "id", "");
		o.whenContext = propGet(props, "when-context", "");
		o.formats = propGet(props, "formats", "");
		if (o.id.length)
			opts ~= o;
	}
	return opts;
}

private Step chooseFromBody(string propsRaw, string body, int sourceLine)
{
	auto props = parseProps(propsRaw);
	Step step;
	step.kind = "choose";
	step.id = propGet(props, "id", "");
	step.prompt = propGet(props, "prompt", "");
	step.intent = propGet(props, "intent", "");
	step.tool = propGet(props, "tool", "");
	step.whenContext = propGet(props, "when-context", "");
	step.sourceLine = sourceLine;
	step.options = parseOptions(body);
	if (step.id.length == 0)
		step.id = "choose-" ~ to!string(sourceLine);
	return step;
}

private Step askFromBody(string propsRaw, int sourceLine)
{
	auto props = parseProps(propsRaw);
	Step step;
	step.kind = "ask";
	step.id = propGet(props, "id", "");
	step.prompt = propGet(props, "prompt", "");
	step.sourceLine = sourceLine;
	if (step.id.length == 0)
		step.id = "ask-" ~ to!string(sourceLine);
	return step;
}

/// Parse a CentrMark document for ::: playbook / ::: step profile (subset).
/// Full CentrMark AST remains the long-term path via centrmark-cli; this extracts runnable steps.
Playbook parsePlaybook(string source, string sourcePath = "")
{
	Playbook pb;
	pb.sourcePath = sourcePath;
	pb.shell = "auto";

	auto lines = source.splitLines;
	OpenFence[] stack;
	string[][] bodies; // parallel to stack: accumulated body lines
	bodies.length = 0;

	void push(OpenFence f)
	{
		stack ~= f;
		bodies ~= cast(string[])[];
	}

	void appendBody(string line)
	{
		if (stack.length == 0)
			return;
		bodies[$ - 1] ~= line;
	}

	string joinBody(string[] ls)
	{
		auto buf = appender!string();
		foreach (i, l; ls)
		{
			if (i)
				buf.put('\n');
			buf.put(l);
		}
		return buf.data;
	}

	foreach (idx, line; lines)
	{
		int lineNo = cast(int) idx + 1;
		OpenFence open;
		if (parseDirectiveOpen(line, open))
		{
			open.line = lineNo;
			// closing fence: only colons
			auto stripped = line.strip;
			bool onlyColons = true;
			foreach (ch; stripped)
				if (ch != ':')
				{
					onlyColons = false;
					break;
				}
			if (onlyColons && stack.length > 0 && stripped.length >= stack[$ - 1].len)
			{
				// treat as close if length matches top
				if (isCloseFence(line, stack[$ - 1].len))
				{
					auto top = stack[$ - 1];
					auto body = joinBody(bodies[$ - 1]);
					stack = stack[0 .. $ - 1];
					bodies = bodies[0 .. $ - 1];

					if (top.name == "step")
					{
						auto defaultShell = pb.shell.length ? pb.shell : "auto";
						pb.steps ~= stepFromBody(top.propsRaw, body, top.line, defaultShell);
					}
					else if (top.name == "choose")
					{
						pb.steps ~= chooseFromBody(top.propsRaw, body, top.line);
					}
					else if (top.name == "ask")
					{
						pb.steps ~= askFromBody(top.propsRaw, top.line);
					}
					else if (top.name == "playbook")
					{
						auto props = parseProps(top.propsRaw);
						pb.id = propGet(props, "id", pb.id);
						pb.shell = propGet(props, "shell", pb.shell);
						// Nested steps already collected while inside; body may also
						// contain steps parsed as nested opens — already handled.
					}
					continue;
				}
			}

			if (open.name == "playbook" || open.name == "step"
					|| open.name == "choose" || open.name == "ask")
			{
				if (open.name == "playbook")
				{
					auto props = parseProps(open.propsRaw);
					pb.id = propGet(props, "id", pb.id);
					pb.shell = propGet(props, "shell", pb.shell);
				}
				push(open);
				continue;
			}
		}

		if (stack.length > 0 && isCloseFence(line, stack[$ - 1].len))
		{
			auto top = stack[$ - 1];
			auto body = joinBody(bodies[$ - 1]);
			stack = stack[0 .. $ - 1];
			bodies = bodies[0 .. $ - 1];
			if (top.name == "step")
			{
				auto defaultShell = pb.shell.length ? pb.shell : "auto";
				pb.steps ~= stepFromBody(top.propsRaw, body, top.line, defaultShell);
			}
			else if (top.name == "choose")
			{
				pb.steps ~= chooseFromBody(top.propsRaw, body, top.line);
			}
			else if (top.name == "ask")
			{
				pb.steps ~= askFromBody(top.propsRaw, top.line);
			}
			else if (top.name == "playbook")
			{
				auto props = parseProps(top.propsRaw);
				pb.id = propGet(props, "id", pb.id);
				pb.shell = propGet(props, "shell", pb.shell);
			}
			continue;
		}

		appendBody(line);
	}

	if (pb.id.length == 0 && sourcePath.length)
	{
		import std.path : baseName, stripExtension;

		pb.id = sourcePath.baseName.stripExtension;
	}
	return pb;
}

unittest
{
	auto src = q"CMK
::: playbook [id="install-gh" shell="auto"]
::: choose [id="pkg-format" prompt="How?" intent="cli.install" tool="gh"]
:::
::: step [id="install" intent="cli.install" tool="gh" bind="pkg-format"]
:::
::: step [id="verify" when="install" when-answer="pkg-format=winget"]
```
gh --version
```
:::
:::
CMK";
	auto pb = parsePlaybook(src, "t.cmk");
	assert(pb.id == "install-gh");
	assert(pb.steps.length == 3);
	assert(pb.steps[0].kind == "choose");
	assert(pb.steps[0].tool == "gh");
	assert(pb.steps[1].intent == "cli.install");
	assert(pb.steps[1].bind == "pkg-format");
	assert(pb.steps[2].whenAnswer == "pkg-format=winget");
}
