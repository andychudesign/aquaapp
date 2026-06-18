# Reading Build Settings

How to read effective build settings during a security audit in Cursor.

## Getting build settings

Cursor has no `GetTargetBuildSettings` MCP tool. Read effective settings with `xcodebuild`:

```sh
xcodebuild -showBuildSettings -json -project <name>.xcodeproj -target <target> -configuration <config>
```

Use `-workspace <name>.xcworkspace -scheme <scheme>` instead of `-project`/`-target` when the project is workspace-based.

For large outputs, redirect to a file and run the filter script rather than reading the file linearly:

```sh
xcodebuild -showBuildSettings -json -project <name>.xcodeproj -target <target> > /tmp/build-settings.json
python3 .cursor/skills/audit-xcode-security-settings/scripts/filter_build_settings.py /tmp/build-settings.json
```

## Schema

`xcodebuild -showBuildSettings -json` returns a dictionary keyed by target name, each with a `buildSettings` object of `SETTING_NAME: value` pairs.

When using the filter script on saved output, it accepts either:
- `xcodebuild -showBuildSettings -json` output (target-keyed dictionary), or
- A flat `{ "buildSettings": [ { "macroName", "evaluatedValue", ... } ] }` array (legacy Xcode MCP shape).

Field reference for the legacy array shape:

- **`macroName`** — setting name (always present).
- **`evaluatedValue`** — fully resolved value after `$(...)` macro expansion. This is what the build actually sees. Use this for audit decisions. May be omitted when the resolved value is empty — treat its absence as an empty string.
- **`value`** — raw, unexpanded value as written in the source (often missing).
- **`targetValue`** — present only when the setting is explicitly set at the **target** level (vs. inherited from project level). Use this to detect per-target overrides.

## Filter recipes

The script lives at `scripts/filter_build_settings.py` (relative to the skill root). It derives its filter regex from `references/settings-and-entitlements-catalog.md` at runtime, so adding settings to the catalog automatically extends the filter. Override with `--regex` if you need a narrower filter.

### Compact `name=value` view

```sh
python3 scripts/filter_build_settings.py <saved-file>
```

### With explicit target-override flag

```sh
python3 scripts/filter_build_settings.py <saved-file> --show-overrides
```

### Only catalog settings NOT at a hardened value (the "what's left to do" view)

```sh
python3 scripts/filter_build_settings.py <saved-file> --unhardened-only
```

The `--show-overrides` and `--unhardened-only` flags can be combined.
