module scriptbook_cli.main;

import std.algorithm : startsWith;
import std.file : exists, readText;
import std.path : absolutePath;
import std.stdio : stderr, writefln, writeln;

import scriptbook.parse;
import scriptbook.run;
import scriptbook.sidecar;

enum string CLI_VERSION = "0.1.0";

private void usage()
{
	writeln("scriptbook " ~ CLI_VERSION);
	writeln("");
	writeln("Usage:");
	writeln("  scriptbook run <file.cmk> [--yes] [--dry-run]");
	writeln("  scriptbook status <file.cmk>");
	writeln("  scriptbook clean-runs <file.cmk>");
	writeln("  scriptbook version");
	writeln("");
	writeln("Run output is written to <file.cmk>.runs/ (sidecar). The .cmk is never modified.");
}

private int cmdRun(string path, bool yes, bool dryRun)
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
	foreach (s; pb.steps)
		writefln("  - %s  shell=%s cwd=%s confirm=%s when=%s", s.id, s.shell, s.cwd, s.confirm, s.when);

	if (!hasRuns(abs))
	{
		writeln("no sidecar runs yet (run: scriptbook run " ~ path ~ ")");
		return 0;
	}
	writeln("");
	writeln("last run index:");
	writeln(readIndexRaw(abs));
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
	case "run":
		{
			if (args.length < 3)
			{
				usage();
				return 1;
			}
			bool yes = false;
			bool dryRun = false;
			string file;
			foreach (a; args[2 .. $])
			{
				if (a == "--yes" || a == "-y")
					yes = true;
				else if (a == "--dry-run")
					dryRun = true;
				else if (!a.startsWith("-"))
					file = a;
			}
			if (file.length == 0)
			{
				usage();
				return 1;
			}
			return cmdRun(file, yes, dryRun);
		}
	case "status":
		if (args.length < 3)
		{
			usage();
			return 1;
		}
		return cmdStatus(args[2]);
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
