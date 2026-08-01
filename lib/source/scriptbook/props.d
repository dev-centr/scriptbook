module scriptbook.props;

import std.algorithm : endsWith, startsWith;
import std.array : appender;
import std.string : strip;

/// Parse CentrMark-style props: id="x" shell="auto" confirm=true
string[string] parseProps(string raw)
{
	string[string] outMap;
	if (raw.length == 0)
		return outMap;

	string s = raw.strip;
	if (s.startsWith("["))
		s = s[1 .. $];
	if (s.endsWith("]"))
		s = s[0 .. $ - 1];
	s = s.strip;

	size_t i = 0;
	while (i < s.length)
	{
		while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == ','))
			i++;
		if (i >= s.length)
			break;

		size_t keyStart = i;
		while (i < s.length && s[i] != '=' && s[i] != ' ' && s[i] != '\t')
			i++;
		string key = s[keyStart .. i].strip;
		if (key.length == 0)
			break;

		while (i < s.length && (s[i] == ' ' || s[i] == '\t'))
			i++;
		if (i >= s.length || s[i] != '=')
		{
			outMap[key] = "true";
			continue;
		}
		i++; // =
		while (i < s.length && (s[i] == ' ' || s[i] == '\t'))
			i++;
		if (i >= s.length)
		{
			outMap[key] = "";
			break;
		}

		string val;
		if (s[i] == '"' || s[i] == '\'')
		{
			char q = s[i];
			i++;
			auto buf = appender!string();
			while (i < s.length && s[i] != q)
			{
				if (s[i] == '\\' && i + 1 < s.length)
				{
					buf.put(s[i + 1]);
					i += 2;
				}
				else
				{
					buf.put(s[i]);
					i++;
				}
			}
			if (i < s.length && s[i] == q)
				i++;
			val = buf.data;
		}
		else
		{
			size_t vStart = i;
			while (i < s.length && s[i] != ' ' && s[i] != '\t' && s[i] != ',')
				i++;
			val = s[vStart .. i];
		}
		outMap[key] = val;
	}
	return outMap;
}

string propGet(string[string] props, string key, string def = "")
{
	if (auto p = key in props)
		return *p;
	return def;
}

bool propBool(string[string] props, string key, bool def = false)
{
	auto v = propGet(props, key, "");
	if (v.length == 0)
		return def;
	import std.uni : toLower;

	auto l = v.toLower;
	return l == "true" || l == "yes" || l == "1";
}
