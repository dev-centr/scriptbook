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
	string runtime;
	string intent;
	string tool;
	string context;
	string format;
	string resolvedCommand;
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
	string hostFamily;
	string hostDistro;
	string hostArch;
	string hostContext;
	string[] hostOverlays;
	string[string] answers;
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
		~ `"runtime":"` ~ jsonEscape(r.runtime) ~ `",`
		~ `"intent":"` ~ jsonEscape(r.intent) ~ `",`
		~ `"tool":"` ~ jsonEscape(r.tool) ~ `",`
		~ `"context":"` ~ jsonEscape(r.context) ~ `",`
		~ `"format":"` ~ jsonEscape(r.format) ~ `",`
		~ `"resolvedCommand":"` ~ jsonEscape(r.resolvedCommand) ~ `",`
		~ `"startedAt":"` ~ jsonEscape(r.startedAt) ~ `",`
		~ `"finishedAt":"` ~ jsonEscape(r.finishedAt) ~ `",`
		~ `"durationMs":` ~ to!string(r.durationMs) ~ `,`
		~ `"status":"` ~ jsonEscape(r.status) ~ `",`
		~ `"message":"` ~ jsonEscape(r.message) ~ `"`
		~ "}";
}

private string answersToJson(string[string] answers)
{
	string[] parts;
	foreach (k, v; answers)
		parts ~= `"` ~ jsonEscape(k) ~ `":"` ~ jsonEscape(v) ~ `"`;
	return "{" ~ parts.join(",") ~ "}";
}

private string overlaysToJson(string[] overlays)
{
	return "[" ~ overlays.map!(s => `"` ~ jsonEscape(s) ~ `"`).array.join(",") ~ "]";
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
		~ `"host":{`
		~ `"family":"` ~ jsonEscape(idx.hostFamily) ~ `",`
		~ `"distro":"` ~ jsonEscape(idx.hostDistro) ~ `",`
		~ `"arch":"` ~ jsonEscape(idx.hostArch) ~ `",`
		~ `"context":"` ~ jsonEscape(idx.hostContext) ~ `",`
		~ `"overlays":` ~ overlaysToJson(idx.hostOverlays)
		~ `},`
		~ `"answers":` ~ answersToJson(idx.answers) ~ `,`
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

/// Parse last-run sidecar into structured form for `scriptbook history`.
RunIndex readRunIndex(string cmkPath)
{
	import std.json : parseJSON, JSONValue;

	RunIndex idx;
	auto raw = readIndexRaw(cmkPath);
	if (!raw.length)
		return idx;
	auto j = parseJSON(raw);
	idx.runId = j["runId"].str;
	idx.playbookId = j["playbookId"].str;
	idx.sourcePath = j["sourcePath"].str;
	idx.startedAt = j["startedAt"].str;
	idx.finishedAt = j["finishedAt"].str;
	idx.exitSummary = cast(int) j["exitSummary"].integer;
	if ("stepOrder" in j)
	{
		foreach (s; j["stepOrder"].array)
			idx.stepOrder ~= s.str;
	}
	if ("results" in j)
	{
		foreach (r; j["results"].array)
		{
			StepResult sr;
			sr.id = r["id"].str;
			sr.exitCode = cast(int) r["exitCode"].integer;
			sr.stdoutText = r["stdout"].str;
			sr.stderrText = r["stderr"].str;
			sr.shell = r["shell"].str;
			if ("runtime" in r)
				sr.runtime = r["runtime"].str;
			if ("intent" in r)
				sr.intent = r["intent"].str;
			if ("tool" in r)
				sr.tool = r["tool"].str;
			if ("context" in r)
				sr.context = r["context"].str;
			if ("format" in r)
				sr.format = r["format"].str;
			if ("resolvedCommand" in r)
				sr.resolvedCommand = r["resolvedCommand"].str;
			sr.startedAt = r["startedAt"].str;
			sr.finishedAt = r["finishedAt"].str;
			sr.durationMs = r["durationMs"].integer;
			sr.status = r["status"].str;
			sr.message = r["message"].str;
			idx.results ~= sr;
		}
	}
	return idx;
}
