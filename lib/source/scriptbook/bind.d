module scriptbook.bind;

import std.algorithm : canFind;
import std.array : appender;
import std.file : exists;
import std.path : buildPath;
import std.process : environment;

import equivalence.cli : CliInstallMethod, HostCaps, listCliInstalls;

import scriptbook.host;
import scriptbook.model;

struct BindOptions
{
	string catalogPath;
	string format;
	bool preferImmutable = true;
	string[string] answers;
}

string findCatalog(string explicitPath)
{
	if (explicitPath.length && exists(explicitPath))
		return explicitPath;
	auto env = environment.get("SCRIPTBOOK_CATALOG");
	if (env.length && exists(env))
		return env;
	string home = environment.get("HOME");
	version (Windows)
	{
		if (home.length == 0)
			home = environment.get("USERPROFILE");
	}
	if (home.length)
	{
		auto cached = buildPath(home, ".dev-center", "equivalence-rules-cli", "repo",
				"catalog", "tools.sdl");
		if (exists(cached))
			return cached;
	}
	string[] relatives = [
		buildPath("..", "equivalence-rules-cli", "catalog", "tools.sdl"),
		buildPath("..", "..", "equivalence-rules-cli", "catalog", "tools.sdl"),
		buildPath("catalog", "tools.sdl"),
	];
	foreach (r; relatives)
		if (exists(r))
			return r;
	return "";
}

HostCaps capsFromHost(HostIdentity h, BindOptions opts)
{
	HostCaps c;
	c.family = h.family;
	c.pms = h.pms.dup;
	// catalog uses "apt" / "homebrew"; probes record apt-get / brew
	if (c.pms.canFind("apt-get"))
		c.pms ~= "apt";
	if (c.pms.canFind("brew"))
		c.pms ~= "homebrew";
	c.formats = h.formats;
	c.runtimes = ["argv"];
	foreach (sh; h.shells)
		c.runtimes ~= sh;
	c.formatFilter = opts.format;
	c.preferImmutable = opts.preferImmutable;
	return c;
}

bool answerMatches(string whenAnswer, string[string] answers)
{
	if (whenAnswer.length == 0)
		return true;
	auto eq = whenAnswer.indexOfEq();
	if (eq < 0)
		return answers.get(whenAnswer, "").length > 0;
	auto key = whenAnswer[0 .. eq];
	auto val = whenAnswer[eq + 1 .. $];
	return answers.get(key, "") == val;
}

private ptrdiff_t indexOfEq(string s)
{
	foreach (i, ch; s)
		if (ch == '=')
			return cast(ptrdiff_t) i;
	return -1;
}

private string methodsHint(CliInstallMethod[] methods)
{
	auto buf = appender!string();
	buf.put("compatible formats:");
	foreach (m; methods)
	{
		buf.put(" ");
		buf.put(m.format.length ? m.format : m.context);
		buf.put("(");
		buf.put(m.context);
		buf.put(")");
	}
	buf.put(" — pass --format <id> or an answers file");
	return buf.data;
}

/// Bind intent/choose cells. Returns an error string if the run must stop.
string bindPlaybook(ref Playbook pb, HostIdentity host, ref BindOptions opts)
{
	auto catalog = findCatalog(opts.catalogPath);
	opts.catalogPath = catalog;
	auto caps = capsFromHost(host, opts);

	foreach (ref step; pb.steps)
	{
		if (step.kind == "choose" && step.intent == "cli.install" && step.tool.length)
		{
			if (catalog.length == 0)
				return "intent choose needs a CLI catalog (set --catalog or SCRIPTBOOK_CATALOG)";
			auto methods = listCliInstalls(catalog, step.tool, caps);
			if (step.options.length)
			{
				CliInstallMethod[] filtered;
				foreach (m; methods)
				{
					bool ok = false;
					foreach (opt; step.options)
					{
						if (opt.whenContext.length
								&& !contextMatches(opt.whenContext, host, m.context))
							continue;
						if (opt.formats.length && opt.formats != m.format && opt.id != m.format)
							continue;
						if (opt.id == m.format || opt.id == m.context || opt.formats == m.format)
							ok = true;
					}
					if (ok)
						filtered ~= m;
				}
				if (filtered.length)
					methods = filtered;
			}
			if (opts.answers.get(step.id, "").length)
				continue;
			if (opts.format.length)
			{
				opts.answers[step.id] = opts.format;
				continue;
			}
			if (methods.length == 1)
			{
				opts.answers[step.id] = methods[0].format;
				continue;
			}
			if (methods.length == 0)
				return "no compatible install method for tool '" ~ step.tool ~ "' on this host";
			return methodsHint(methods);
		}

		if (step.kind != "step" || step.intent.length == 0)
			continue;
		if (step.intent != "cli.install")
			return "unknown intent '" ~ step.intent ~ "' (not registered)";
		if (catalog.length == 0)
			return "intent step needs a CLI catalog (set --catalog or SCRIPTBOOK_CATALOG)";

		auto stepCaps = caps;
		if (step.bind.length)
		{
			auto ans = opts.answers.get(step.bind, "");
			if (ans.length)
				stepCaps.formatFilter = ans;
		}
		if (opts.format.length && stepCaps.formatFilter.length == 0)
			stepCaps.formatFilter = opts.format;

		auto methods = listCliInstalls(catalog, step.tool, stepCaps);
		if (methods.length == 0)
			return "no compatible install method for tool '" ~ step.tool ~ "'";
		if (methods.length > 1 && stepCaps.formatFilter.length == 0)
			return methodsHint(methods);

		auto m = methods[0];
		step.resolvedCommand = m.command;
		step.argv = m.argv;
		step.format = m.format;
		step.context = m.context;
		step.runtime = m.runtime;
	}
	return "";
}
