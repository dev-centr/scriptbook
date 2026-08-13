module scriptbook_cli.main;

import std.algorithm : startsWith;
import std.file : exists, readText;
import std.path : absolutePath;
import std.stdio : stderr, writefln, writeln;

import scriptbook.parse;
import scriptbook.prohelp;
import scriptbook.run;
import scriptbook.sidecar;

enum string CLI_VERSION = "0.2.0";

private void usage()
{
	writeln("scriptbook " ~ CLI_VERSION);
	writeln("");
	writeln("Usage:");
	writeln("  scriptbook run <file.cmk> [--yes] [--dry-run] [--format <id>] [--catalog <tools.sdl>] [--answers <file.json>] [--prefer-mutable]");
	writeln("  scriptbook status <file.cmk>");
	writeln("  scriptbook history <file.cmk>");
	writeln("  scriptbook clean-runs <file.cmk>");
	writeln("  scriptbook prohelp");
	writeln("  scriptbook version");
	writeln("");
	writeln("Run output is written to <file.cmk>.runs/ (sidecar). The .cmk is never modified.");
	writeln("New to audit trails? Run: scriptbook prohelp");
}

private string[string] loadAnswersFile(string path)
{
	import std.json : parseJSON;

	string[string] a;
	if (path.length == 0 || !exists(path))
		return a;
	auto j = parseJSON(readText(path));
	foreach (k, v; j.object)
		a[k] = v.str;
	return a;
}

private int cmdRun(string path, bool yes, bool dryRun, string format, string catalog, string answersPath, bool preferImmutable)
{
	if (!exists(path))
	{
		stderr.writeln("file not found: " ~ path);
		return 1;
	}
	auto abs = absolutePath(path);
	auto pb = parsePlaybook(readText(abs), abs);
	if (pb.steps.length == 0)
	{
		stderr.writeln("no ::: step directives found in " ~ path);
		return 1;
	}
	writefln("playbook id=%s steps=%s", pb.id, pb.steps.length);
	RunOptions opts;
	opts.yes = yes;
	opts.dryRun = dryRun;
	opts.format = format;
	opts.catalogPath = catalog;
	opts.preferImmutable = preferImmutable;
	opts.answers = loadAnswersFile(answersPath);
	auto idx = runPlaybook(pb, opts);
	writeSidecar(abs, idx);
	foreach (r; idx.results)
	{
		writefln("[%s] %s exit=%s (%s ms) %s", r.status, r.id, r.exitCode, r.durationMs, r.message);
		if (r.stdoutText.length)
		{
			writeln("--- stdout ---");
			writeln(r.stdoutText);
		}
		if (r.stderrText.length)
		{
			writeln("--- stderr ---");
			writeln(r.stderrText);
		}
	}
	writefln("sidecar: %s", runsDirFor(abs));
	writeln("Tip: scriptbook history " ~ path ~ "  |  scriptbook prohelp");
	return idx.exitSummary == 0 ? 0 : idx.exitSummary;
}

private int cmdStatus(string path)
{
	if (!exists(path))
	{
		stderr.writeln("file not found: " ~ path);
		return 1;
	}
	auto abs = absolutePath(path);
	auto pb = parsePlaybook(readText(abs), abs);
	writefln("playbook: %s (%s steps)", pb.id, pb.steps.length);
	writefln("source: %s", abs);
	writefln("runs dir: %s", runsDirFor(abs));
	foreach (s; pb.steps)
		writefln("  - %s  shell=%s cwd=%s confirm=%s when=%s", s.id, s.shell, s.cwd, s.confirm, s.when);

	if (!hasRuns(abs))
	{
		writeln("");
		writeln("no sidecar runs yet — this playbook has not been recorded as run on this machine.");
		writeln("  run:     scriptbook run " ~ path);
		writeln("  prohelp: scriptbook prohelp");
		return 0;
	}
	writeln("");
	writeln("last run was recorded. Use `scriptbook history` for a readable table, or see raw index:");
	writeln(readIndexRaw(abs));
	return 0;
}

private int cmdHistory(string path)
{
	if (!exists(path))
	{
		stderr.writeln("file not found: " ~ path);
		return 1;
	}
	auto abs = absolutePath(path);
	if (!hasRuns(abs))
	{
		writeln("No run history for: " ~ abs);
		writeln("Runs directory would be: " ~ runsDirFor(abs));
		writeln("Execute once with: scriptbook run " ~ path);
		writeln("Learn more: scriptbook prohelp");
		return 0;
	}
	auto idx = readRunIndex(abs);
	writefln("Playbook: %s", idx.playbookId.length ? idx.playbookId : "(unknown)");
	writefln("Source:   %s", idx.sourcePath.length ? idx.sourcePath : abs);
	writefln("Run id:   %s", idx.runId);
	writefln("Started:  %s", idx.startedAt);
	writefln("Finished: %s", idx.finishedAt);
	writefln("Exit:     %s", idx.exitSummary);
	writeln("");
	writeln("Step results:");
	foreach (r; idx.results)
	{
		writefln("  [%s] %-24s exit=%-3s %6s ms  %s",
			r.status, r.id, r.exitCode, r.durationMs, r.message);
	}
	writefln("\nSidecar path: %s", runsDirFor(abs));
	writeln("OS-wide logs (syslog/journal/Event Viewer): scriptbook prohelp");
	return 0;
}

private int cmdClean(string path)
{
	auto abs = absolutePath(path);
	cleanRuns(abs);
	writefln("removed %s (if present)", runsDirFor(abs));
	return 0;
}

int main(string[] args)
{
	if (args.length < 2)
	{
		usage();
		return 1;
	}
	auto cmd = args[1];
	switch (cmd)
	{
	case "version":
	case "--version":
	case "-V":
		writeln(CLI_VERSION);
		return 0;
	case "help":
	case "--help":
	case "-h":
		usage();
		return 0;
	case "prohelp":
		printProhelp();
		return 0;
	case "run":
		{
			if (args.length < 3)
			{
				usage();
				return 1;
			}
			bool yes = false;
			bool dryRun = false;
			bool preferImmutable = true;
			string file;
			string format;
			string catalog;
			string answersPath;
			for (size_t i = 2; i < args.length; i++)
			{
				auto a = args[i];
				if (a == "--yes" || a == "-y")
					yes = true;
				else if (a == "--dry-run")
					dryRun = true;
				else if (a == "--prefer-mutable")
					preferImmutable = false;
				else if (a == "--format" && i + 1 < args.length)
					format = args[++i];
				else if (a.startsWith("--format="))
					format = a["--format=".length .. $];
				else if (a == "--catalog" && i + 1 < args.length)
					catalog = args[++i];
				else if (a.startsWith("--catalog="))
					catalog = a["--catalog=".length .. $];
				else if (a == "--answers" && i + 1 < args.length)
					answersPath = args[++i];
				else if (a.startsWith("--answers="))
					answersPath = a["--answers=".length .. $];
				else if (!a.startsWith("-"))
					file = a;
			}
			if (file.length == 0)
			{
				usage();
				return 1;
			}
			return cmdRun(file, yes, dryRun, format, catalog, answersPath, preferImmutable);
		}
	case "status":
		if (args.length < 3)
		{
			usage();
			return 1;
		}
		return cmdStatus(args[2]);
	case "history":
		if (args.length < 3)
		{
			usage();
			return 1;
		}
		return cmdHistory(args[2]);
	case "clean-runs":
		if (args.length < 3)
		{
			usage();
			return 1;
		}
		return cmdClean(args[2]);
	default:
		stderr.writeln("unknown command: " ~ cmd);
		usage();
		return 1;
	}
}
