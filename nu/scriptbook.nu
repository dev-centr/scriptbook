# Scriptbook Nushell helpers — enhanced UX when shell=nu / status tables.
# Usage from a Nu session next to this file:
#   use ./scriptbook.nu
#   scriptbook status examples/smoke.cmk

export def "scriptbook status" [file: path] {
  ^scriptbook status $file
}

export def "scriptbook run" [file: path, --yes, --dry-run] {
  mut args = [$file]
  if $yes { $args = ($args | append "--yes") }
  if $dry_run { $args = ($args | append "--dry-run") }
  ^scriptbook run ...$args
}

export def "scriptbook clean-runs" [file: path] {
  ^scriptbook clean-runs $file
}

# Summarize sidecar index.json as a table (if present).
export def "scriptbook runs" [file: path] {
  let dir = $"($file).runs"
  let index = $"($dir)/index.json"
  if not ($index | path exists) {
    print $"no sidecar at ($dir)"
    return
  }
  open $index
  | get results?
  | default []
  | select id status exitCode durationMs message?
}
