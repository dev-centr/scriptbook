module scriptbook.host;

import std.algorithm : canFind, splitter, startsWith;
import std.file : exists;
import std.json : parseJSON;
import std.path : buildPath, pathSeparator;
import std.process : environment, execute;
import std.string : split, strip, toLower;

/// Frozen snapshot. Nested intent expansion must reuse this. Do not probe twice.
struct HostIdentity
{
	string family;
	string distro;
	string[] like;
	string version_;
	string arch;
	string[] overlays;
	string[] shells;
	string[] pms;
	string[] formats;
	string context; // convenience alias e.g. windows/winget
	string rulesRevision;
}

private bool pathHas(string name)
{
	auto path = environment.get("PATH");
	if (path.length == 0)
		return false;
	version (Windows)
	{
		string[] exts = [".exe", ".cmd", ".bat", ".com", ""];
		foreach (dir; path.splitter(pathSeparator))
		{
			foreach (ext; exts)
			{
				if (exists(buildPath(dir, name ~ ext)))
					return true;
			}
		}
		return false;
	}
	else
	{
		foreach (dir; path.splitter(pathSeparator))
		{
			if (exists(buildPath(dir, name)))
				return true;
		}
		return false;
	}
}

private void addUnique(ref string[] arr, string v)
{
	if (v.length && !arr.canFind(v))
		arr ~= v;
}

private string unameField(string flag)
{
	auto r = execute(["uname", flag]);
	if (r.status != 0)
		return "";
	return r.output.strip;
}

private void readOsRelease(ref HostIdentity h, string path)
{
	if (!exists(path))
		return;
	import std.file : readText;
	import std.string : splitLines, startsWith;

	foreach (line; readText(path).splitLines)
	{
		auto s = line.strip;
		if (s.startsWith("ID="))
		{
			auto v = s[3 .. $];
			if (v.length >= 2 && v[0] == '"' && v[$ - 1] == '"')
				v = v[1 .. $ - 1];
			h.distro = v;
		}
		else if (s.startsWith("ID_LIKE="))
		{
			auto v = s[8 .. $];
			if (v.length >= 2 && v[0] == '"' && v[$ - 1] == '"')
				v = v[1 .. $ - 1];
			foreach (p; v.split(" "))
				addUnique(h.like, p.strip);
		}
		else if (s.startsWith("VERSION_ID="))
		{
			auto v = s[11 .. $];
			if (v.length >= 2 && v[0] == '"' && v[$ - 1] == '"')
				v = v[1 .. $ - 1];
			h.version_ = v;
		}
	}
}

private string pmToFormat(string pm)
{
	switch (pm)
	{
	case "apt-get":
	case "apt":
		return "deb";
	case "dnf":
		return "rpm";
	case "homebrew":
	case "brew":
		return "brew";
	case "msiexec":
		return "msi";
	default:
		return pm;
	}
}

private string pickContext(HostIdentity h, bool preferImmutable)
{
	if (preferImmutable && h.pms.canFind("nix"))
	{
		if (h.family == "darwin")
			return "macos/nix/default";
		if (h.family == "linux")
			return "linux/nix/default";
	}
	if (h.family == "windows")
	{
		if (h.pms.canFind("winget"))
			return "windows/winget";
		if (h.pms.canFind("scoop"))
			return "windows/scoop";
		if (h.pms.canFind("choco"))
			return "windows/choco";
	}
	if (h.family == "darwin")
	{
		if (h.pms.canFind("brew"))
			return "macos/homebrew";
	}
	if (h.family == "linux")
	{
		if (h.pms.canFind("apt-get"))
			return h.distro == "ubuntu" ? "linux/ubuntu/default" : "linux/debian/default";
		if (h.pms.canFind("dnf"))
			return "linux/fedora/default";
		if (h.pms.canFind("pacman"))
			return "linux/arch/default";
		if (h.pms.canFind("apk"))
			return "linux/alpine/default";
		if (h.pms.canFind("brew"))
			return "linux/homebrew";
	}
	if (h.pms.canFind("npm"))
		return "default/npm-global";
	return "";
}

/// Walk the baked probe cascade. Does not call the Equivalence Engine.
HostIdentity detectHost(bool preferImmutable = true)
{
	enum string baked = import("probes.generated.json");
	auto j = parseJSON(baked);
	HostIdentity h;
	if ("rulesRevision" in j)
		h.rulesRevision = j["rulesRevision"].str;

	foreach (probe; j["probes"].array)
	{
		auto kind = probe["kind"].str;
		if (kind == "compileTime")
		{
			version (Windows)
			{
				h.family = "windows";
				h.distro = "windows";
			}
			else version (OSX)
			{
				h.family = "darwin";
				h.distro = "macos";
			}
			else
			{
				h.family = "linux";
			}
			version (X86_64)
				h.arch = "x86_64";
			else version (AArch64)
				h.arch = "aarch64";
			else
				h.arch = "";
		}
		else if (kind == "uname")
		{
			version (Windows)
			{
			}
			else
			{
				auto sys = unameField("-s").toLower;
				if (sys.canFind("linux"))
					h.family = "linux";
				else if (sys.canFind("darwin"))
				{
					h.family = "darwin";
					h.distro = "macos";
				}
				else if (sys.canFind("freebsd"))
					h.family = "freebsd";
				auto mach = unameField("-m");
				if (mach.length)
					h.arch = mach == "amd64" ? "x86_64" : mach;
			}
		}
		else if (kind == "osReleaseFile")
		{
			auto p = "path" in probe ? probe["path"].str : "/etc/os-release";
			readOsRelease(h, p);
		}
		else if (kind == "ntVersion")
		{
			version (Windows)
			{
				auto v = environment.get("OS");
				if (v.length && h.version_.length == 0)
					h.version_ = v;
			}
		}
		else if (kind == "pathHas")
		{
			if ("names" in probe)
			{
				foreach (n; probe["names"].array)
				{
					auto name = n.str;
					if (!pathHas(name))
						continue;
					switch (name)
					{
					case "nu", "pwsh", "bash", "sh":
						addUnique(h.shells, name);
						break;
					case "apt-get", "dnf", "pacman", "apk", "nix", "guix",
							"winget", "scoop", "choco", "brew", "flatpak",
							"snap", "npm", "pnpm", "msiexec":
						addUnique(h.pms, name);
						addUnique(h.formats, pmToFormat(name));
						break;
					default:
						addUnique(h.pms, name);
						break;
					}
				}
			}
		}
	}

	version (Windows)
	{
	}
	else
	{
		if (exists("/proc/version"))
		{
			import std.file : readText;

			auto pv = readText("/proc/version").toLower;
			if (pv.canFind("microsoft") || pv.canFind("wsl"))
				addUnique(h.overlays, "wsl");
		}
	}

	addUnique(h.formats, "script");
	if (h.family == "windows")
		addUnique(h.formats, "exe");
	if (h.family == "linux")
		addUnique(h.formats, "appimage");

	h.context = pickContext(h, preferImmutable);
	return h;
}

bool contextMatches(string pattern, HostIdentity h, string boundContext)
{
	if (pattern.length == 0)
		return true;
	import equivalence.cli : normalizeFamily;

	if (pattern.length >= 2 && pattern[$ - 2 .. $] == "/*")
	{
		auto prefix = pattern[0 .. $ - 2];
		if (normalizeFamily(h.family) == normalizeFamily(prefix))
			return true;
		if (boundContext == prefix || boundContext.startsWith(prefix ~ "/"))
			return true;
		if (h.context.startsWith(prefix ~ "/") || h.context == prefix)
			return true;
		return false;
	}
	if (boundContext == pattern || h.context == pattern)
		return true;
	return normalizeFamily(h.family) == normalizeFamily(pattern);
}

unittest
{
	auto h = detectHost();
	assert(h.family.length);
	assert(h.rulesRevision == "stage0-handwritten");
}
