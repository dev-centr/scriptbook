module scriptbook.run;

import std.conv : to;
import std.datetime : Clock, UTC;
import std.file : exists, remove, tempDir, write;
import std.path : buildPath;
import std.process : Config, execute, executeShell;
import std.uuid : randomUUID;

import scriptbook.bind;
import scriptbook.host;
import scriptbook.model;
import scriptbook.sidecar;

version (Windows)
	enum bool OnWindows = true;
else
	enum bool OnWindows = false;

private string findOnPath(string name)
{
	version (Windows)
	{
		auto r = execute(["where", name]);
		if (r.status == 0 && r.output.length)
			return name;
		return "";
	}
	else
	{
		auto r = execute(["which", name]);
		if (r.status == 0 && r.output.length)
			return name;
		return "";
	}
}

string resolveShell(string requested)
{
	auto r = requested.length ? requested : "auto";
	if (r == "auto")
	{
		if (findOnPath("nu").length)
			return "nu";
		if (OnWindows)
		{
			if (findOnPath("pwsh").length)
				return "pwsh";
			return "powershell";
		}
		if (findOnPath("bash").length)
			return "bash";
		return "sh";
	}
	return r;
}

private string scriptExt(string shell)
{
	switch (shell)
	{
	case "nu":
		return ".nu";
	case "pwsh":
	case "powershell":
		return ".ps1";
	default:
		return ".sh";
	}
}

private string[] shellCommand(string shell, string scriptPath)
{
	switch (shell)
	{
	case "nu":
		return ["nu", scriptPath];
	case "pwsh":
		return ["pwsh", "-NoProfile", "-File", scriptPath];
	case "powershell":
		return ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath];
	case "bash":
		return ["bash", scriptPath];
	case "sh":
		return ["sh", scriptPath];
	default:
		return [shell, scriptPath];
	}
}

private bool priorOk(string whenId, StepResult[] done)
{
	if (whenId.length == 0)
		return true;
	foreach (r; done)
		if (r.id == whenId)
			return r.status == "ok" && r.exitCode == 0;
	return false;
}

struct RunOptions
{
	bool yes;
	bool dryRun;
	string catalogPath;
	string format;
	bool preferImmutable = true;
	string[string] answers;
}

RunIndex runPlaybook(Playbook pb, RunOptions opts)
{
	RunIndex idx;
	idx.runId = randomUUID().toString();
	idx.playbookId = pb.id;
	idx.sourcePath = pb.sourcePath;
	idx.startedAt = isoNow();
	idx.exitSummary = 0;

	auto host = detectHost(opts.preferImmutable);
	idx.hostFamily = host.family;
	idx.hostDistro = host.distro;
	idx.hostArch = host.arch;
	idx.hostContext = host.context;
	idx.hostOverlays = host.overlays;

	BindOptions bopts;
	bopts.catalogPath = opts.catalogPath;
	bopts.format = opts.format;
	bopts.preferImmutable = opts.preferImmutable;
	bopts.answers = opts.answers;
	auto bindErr = bindPlaybook(pb, host, bopts);
	idx.answers = bopts.answers;
	if (bindErr.length)
	{
		StepResult br;
		br.id = "bind";
		br.status = "blocked";
		br.message = bindErr;
		br.exitCode = 2;
		br.startedAt = isoNow();
		br.finishedAt = isoNow();
		idx.results ~= br;
		idx.stepOrder ~= "bind";
		idx.exitSummary = 2;
		idx.finishedAt = isoNow();
		return idx;
	}

	foreach (step; pb.steps)
	{
		if (step.kind == "choose" || step.kind == "ask")
		{
			idx.stepOrder ~= step.id;
			StepResult cr;
			cr.id = step.id;
			cr.status = "ok";
			cr.message = step.kind ~ " " ~ idx.answers.get(step.id, "(unset)");
			cr.exitCode = 0;
			cr.startedAt = isoNow();
			cr.finishedAt = isoNow();
			idx.results ~= cr;
			continue;
		}

		idx.stepOrder ~= step.id;

		StepResult result;
		result.id = step.id;
		result.startedAt = isoNow();
		result.intent = step.intent;
		result.tool = step.tool;
		result.format = step.format;
		result.context = step.context;
		result.resolvedCommand = step.resolvedCommand;
		result.runtime = step.runtime;
		result.shell = step.intent.length ? "" : resolveShell(step.shell.length ? step.shell : pb.shell);

		if (!priorOk(step.when, idx.results))
		{
			result.status = "skipped";
			result.message = "when condition not met: " ~ step.when;
			result.exitCode = 0;
			result.finishedAt = isoNow();
			result.durationMs = 0;
			idx.results ~= result;
			continue;
		}

		if (!answerMatches(step.whenAnswer, idx.answers))
		{
			result.status = "skipped";
			result.message = "when-answer not met: " ~ step.whenAnswer;
			result.exitCode = 0;
			result.finishedAt = isoNow();
			idx.results ~= result;
			continue;
		}

		if (!contextMatches(step.whenContext, host, step.context.length ? step.context : host.context))
		{
			result.status = "skipped";
			result.message = "when-context not met: " ~ step.whenContext;
			result.exitCode = 0;
			result.finishedAt = isoNow();
			idx.results ~= result;
			continue;
		}

		if (step.confirm && !opts.yes)
		{
			result.status = "blocked";
			result.message = "confirm=true requires --yes";
			result.exitCode = 2;
			result.finishedAt = isoNow();
			idx.exitSummary = 2;
			idx.results ~= result;
			break;
		}

		if (opts.dryRun)
		{
			result.status = "ok";
			result.message = "dry-run";
			result.stdoutText = step.resolvedCommand.length ? step.resolvedCommand : step.script;
			result.exitCode = 0;
			result.finishedAt = isoNow();
			idx.results ~= result;
			continue;
		}

		auto start = Clock.currTime(UTC());

		try
		{
			string workDir = step.cwd == "." ? null : step.cwd;
			int status;
			string output;
			if (step.intent.length && step.argv.length)
			{
				auto rr = execute(step.argv, null, Config.none, size_t.max, workDir);
				status = rr.status;
				output = rr.output;
			}
			else if (step.intent.length && step.resolvedCommand.length)
			{
				auto rr = executeShell(step.resolvedCommand, null, Config.none, size_t.max, workDir);
				status = rr.status;
				output = rr.output;
			}
			else
			{
				auto tmp = buildPath(tempDir(), "scriptbook-" ~ step.id ~ "-" ~ idx.runId[0 .. 8] ~ scriptExt(
						result.shell));
				write(tmp, step.script ~ "\n");
				scope (exit)
				{
					if (exists(tmp))
						remove(tmp);
				}
				auto cmd = shellCommand(result.shell, tmp);
				auto rr = execute(cmd, null, Config.none, size_t.max, workDir);
				status = rr.status;
				output = rr.output;
			}
			result.exitCode = status;
			result.stdoutText = output;
			result.stderrText = "";
			result.status = status == 0 ? "ok" : "failed";
			if (status != 0)
				idx.exitSummary = status;
		}
		catch (Exception e)
		{
			result.exitCode = 127;
			result.stderrText = e.msg;
			result.status = "failed";
			result.message = e.msg;
			idx.exitSummary = 127;
		}

		auto end = Clock.currTime(UTC());
		result.finishedAt = end.toISOExtString();
		result.durationMs = (end - start).total!"msecs";
		idx.results ~= result;

		if (result.status == "failed")
			break;
	}

	idx.finishedAt = isoNow();
	return idx;
}
