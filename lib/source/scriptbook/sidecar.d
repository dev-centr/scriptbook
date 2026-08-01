module scriptbook.sidecar;

import std.algorithm : map;
import std.array : array, join;
import std.conv : to;
import std.datetime : Clock, SysTime, UTC;
import std.file : exists, mkdirRecurse, readText, remove, rmdirRecurse, write;
import std.path : buildPath;
import std.string : replace;

import scriptbook.model;

struct StepResult
{
	string id;
	int exitCode;
	string stdoutText;
	string stderrText;
	string shell;
	string startedAt;
	string finishedAt;
	long durationMs;
	string status; // ok|failed|skipped|blocked
	string message;
}

struct RunIndex
{
	string runId;
	string playbookId;
	string sourcePath;
	string startedAt;
	string finishedAt;
	string[] stepOrder;
	int exitSummary; // max/nonzero prefer
	StepResult[] results;
}

string runsDirFor(string cmkPath)
{
	return cmkPath ~ ".runs";
}

string isoNow()
{
	return Clock.currTime(UTC()).toISOExtString();
}

string jsonEscape(string s)
{
	auto t = s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r")
		.replace("\t", "\\t");
	return t;
}

string stepResultToJson(StepResult r)
{
	return "{"
		~ `"id":"` ~ jsonEscape(r.id) ~ `",`
		~ `"exitCode":` ~ to!string(r.exitCode) ~ `,`
		~ `"stdout":"` ~ jsonEscape(r.stdoutText) ~ `",`
		~ `"stderr":"` ~ jsonEscape(r.stderrText) ~ `",`
		~ `"shell":"` ~ jsonEscape(r.shell) ~ `",`
		~ `"startedAt":"` ~ jsonEscape(r.startedAt) ~ `",`
		~ `"finishedAt":"` ~ jsonEscape(r.finishedAt) ~ `",`
		~ `"durationMs":` ~ to!string(r.durationMs) ~ `,`
		~ `"status":"` ~ jsonEscape(r.status) ~ `",`
		~ `"message":"` ~ jsonEscape(r.message) ~ `"`
		~ "}";
}

string runIndexToJson(RunIndex idx)
{
	auto steps = idx.stepOrder.map!(s => `"` ~ jsonEscape(s) ~ `"`).array.join(",");
	auto results = idx.results.map!(r => stepResultToJson(r)).array.join(",");
	return "{"
		~ `"runId":"` ~ jsonEscape(idx.runId) ~ `",`
		~ `"playbookId":"` ~ jsonEscape(idx.playbookId) ~ `",`
		~ `"sourcePath":"` ~ jsonEscape(idx.sourcePath) ~ `",`
		~ `"startedAt":"` ~ jsonEscape(idx.startedAt) ~ `",`
		~ `"finishedAt":"` ~ jsonEscape(idx.finishedAt) ~ `",`
		~ `"exitSummary":` ~ to!string(idx.exitSummary) ~ `,`
		~ `"stepOrder":[` ~ steps ~ `],`
		~ `"results":[` ~ results ~ `]`
		~ "}";
}

void writeSidecar(string cmkPath, RunIndex idx)
{
	auto dir = runsDirFor(cmkPath);
	mkdirRecurse(dir);
	write(buildPath(dir, "index.json"), runIndexToJson(idx));
	foreach (r; idx.results)
		write(buildPath(dir, r.id ~ ".json"), stepResultToJson(r));
}

void cleanRuns(string cmkPath)
{
	auto dir = runsDirFor(cmkPath);
	if (exists(dir))
		rmdirRecurse(dir);
}

bool hasRuns(string cmkPath)
{
	return exists(buildPath(runsDirFor(cmkPath), "index.json"));
}

string readIndexRaw(string cmkPath)
{
	auto p = buildPath(runsDirFor(cmkPath), "index.json");
	if (!exists(p))
		return "";
	return readText(p);
}
