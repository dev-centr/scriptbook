module scriptbook.prohelp;

import std.stdio : writeln, writefln;

/// Print discoverability / audit guidance (OS tools + Scriptbook sidecars).
void printProhelp()
{
	writeln("scriptbook prohelp — discoverable run history & system audit");
	writeln("");
	writeln("SCRIPTBOOK HISTORY (preferred)");
	writeln("  Every successful or failed `scriptbook run` writes a durable sidecar:");
	writeln("    <file.cmk>.runs/index.json     — last run summary");
	writeln("    <file.cmk>.runs/<step-id>.json — per-step stdout/stderr/status");
	writeln("  Inspect:");
	writeln("    scriptbook status <file.cmk>   — playbook steps + last run");
	writeln("    scriptbook history <file.cmk>  — human-readable last-run table");
	writeln("  The .cmk document is never rewritten; history lives beside it.");
	writeln("");
	writeln("WHY THIS EXISTS");
	writeln("  Classical shell scripts often change machine state with no easy record.");
	writeln("  Scriptbook makes prior runs and results discoverable without tribal knowledge.");
	writeln("");
	writeln("OS AUDIT SURFACES (when you need system-wide logs)");
	version (Windows)
	{
		writeln("  Windows Event Viewer:");
		writeln("    UI: Start → Event Viewer (eventvwr.msc)");
		writeln("    CLI: wevtutil qe System /c:20 /f:text");
		writeln("         Get-WinEvent -LogName System -MaxEvents 20   (PowerShell)");
		writeln("  PowerShell history (session): Get-History");
		writeln("  Scriptbook does not replace Event Viewer; it links you here when needed.");
	}
	else version (linux)
	{
		writeln("  systemd journal:");
		writeln("    journalctl -n 50 --no-pager");
		writeln("    journalctl -u <service> -n 50");
		writeln("  syslog (if present): /var/log/syslog  or  /var/log/messages");
		writeln("  Prefer journalctl on modern distros.");
	}
	else version (OSX)
	{
		writeln("  macOS Unified Logging:");
		writeln("    log show --last 1h --style compact");
		writeln("    Console.app for interactive browsing");
	}
	else
	{
		writeln("  Consult your OS documentation for syslog / journal / Event Viewer.");
	}
	writeln("");
	writeln("RELATED COMMANDS");
	writeln("  scriptbook run <file.cmk> [--yes] [--dry-run]");
	writeln("  scriptbook status <file.cmk>");
	writeln("  scriptbook history <file.cmk>");
	writeln("  scriptbook clean-runs <file.cmk>");
	writeln("  scriptbook version");
}
