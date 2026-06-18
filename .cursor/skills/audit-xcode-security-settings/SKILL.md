---
name: audit-xcode-security-settings
description: Audit and enable security-oriented Xcode build settings. Progressively enables compiler warnings, static analyzer checkers, and Enhanced Security features. Use when the user wants to secure their Xcode project, audit security settings, enable hardening, review the security posture of a build configuration, set up security-focused static analysis, enable static analysis, improve warning coverage, harden diagnostics, or catch more bugs at compile time in C/C++/Objective-C/Swift. Skip for network security (TLS/ATS), code signing, and privacy APIs.
---
# Audit Xcode Security Settings

Assess an Xcode project's security posture and progressively enable security build settings and entitlements — from broadly applicable warnings through Enhanced Security hardening.

## Tool Preferences

Cursor has no dedicated Xcode tooling, so this skill works directly against the project files on disk.

- **Glob** for file discovery (e.g. `**/*.xcodeproj`, `**/*.swift`, `**/*.entitlements`).
- **Grep** for content search across `.pbxproj`, `.xcconfig`, and entitlement plists.
- **Read** for file contents.
- **StrReplace** / **Write** for editing `.pbxproj`, `.xcconfig`, and `.entitlements` files.
- **Shell** for operations the file tools cannot do: reading effective build settings (`xcodebuild -showBuildSettings -json`), `plutil` for plist editing/validation, and `git` operations.

Read effective build settings with:

```sh
xcodebuild -showBuildSettings -json -project <name>.xcodeproj -target <target> -configuration <config>
```

Use `-workspace <name>.xcworkspace -scheme <scheme>` instead of `-project`/`-target` when the project is workspace-based. See `references/reading-build-settings.md` for the output schema and the filter script (`scripts/filter_build_settings.py`). For large outputs, redirect to a file and run the filter script rather than reading the file linearly.

There is no Xcode API to write build settings, so apply changes by editing the project files directly (see "How to apply build settings" in Phase 2).

## Workflow

## Phase 0: Discovery

Identify the project root, the `.xcodeproj`/`.xcworkspace`, and the active scheme. The workspace path is in your context; locate the Xcode project with `Glob` (`**/*.xcodeproj`, `**/*.xcworkspace`). List schemes with `xcodebuild -list -json` if needed.

## Track Progress

Before starting Phase 1:

1. Print the workflow plan to the user as a visible bullet list (so non-verbose users can see what's coming):

   > Workflow:
   > - Phase 1: Analyze project and existing settings
   > - Phase 2: Apply settings
   >     - Step 1: Enhanced Security
   >     - Step 2: Basic Clang safety warnings
   > - Phase 3: Inquire about disabled settings
   > - Phase 4: Validate applied settings
   > - Phase 5: Report and update decision document
   > - Phase 6: Optional follow-ups

2. Call `TodoWrite` with the same items so verbose users get a tracker.

When entering each phase or sub-step:
- Print one line: "▶ Phase N: …" (or "▶ Phase 2 / Step 1: …" for sub-steps).
- Update the todo to `in_progress`.

When finishing each phase or sub-step:
- Print one line: "✓ Phase N: …" (with a brief outcome if applicable, e.g., "✓ Phase 3: No disabled settings found.").
- Update the todo to `completed`.

Phase 6 starts as a single todo and a single line. When the user opts into a specific follow-up, print "▶ Phase 6 / <name>" at start and "✓ Phase 6 / <name>" at end, and create/update the corresponding sub-todo.

### Phase 1: Analyze Project and Settings

No user interaction. Gather facts silently with `Glob`, `Grep`, and `Read`.

1. Find `.xcodeproj` or `.xcworkspace` via `Glob` (`**/*.xcodeproj`, `**/*.xcworkspace`).
2. Search for an existing decision document (`**/xcode-security-settings.md`) via `Glob`. If found, read it and extract: languages and all prior setting decisions with their statuses and rationale. This informs subsequent phases.
3. Detect languages present via `Glob`:
   - `**/*.c` → C
   - `**/*.cpp`, `**/*.cxx`, `**/*.cc` → C++
   - `**/*.m` → Objective-C
   - `**/*.mm` → Objective-C++
   - `**/*.swift` → Swift
4. Enumerate targets and their entitlements files — for each target, record its product type, platform (via `SDKROOT` / `SUPPORTED_PLATFORMS`), and resolve `CODE_SIGN_ENTITLEMENTS` to the on-disk `.entitlements` path (per configuration if it varies). Phase 2 Step 1 needs this map. Read effective values with `xcodebuild -showBuildSettings -json`; see `references/reading-build-settings.md` for the output schema and the recipe for handling large results.

### Phase 2: Apply Settings

Apply settings progressively, from most applicable to least.

**Check existing security settings.** Grep pbxproj and xcconfig files for settings from the catalog (see `references/settings-and-entitlements-catalog.md`). Only apply settings that aren't already set. If everything is already enabled, tell the user and stop.

**How to apply build settings:**
- **Project uses `.xcconfig` files** — edit the xcconfig directly with `StrReplace`/`Write`. Supports both project-level and target-level settings.
- **Project uses `.pbxproj` only** — edit the `project.pbxproj` directly with `StrReplace`. Add the setting to the relevant `XCBuildConfiguration` `buildSettings` block: the project-level configuration for project-wide settings, or the target's configuration for target-level settings. Match the file's existing formatting and quoting exactly.
- **Mixed** — if a target has an `.xcconfig` file, edit the xcconfig. Otherwise, edit the `project.pbxproj`. Never introduce a new configuration method.

Prefer project-level when possible (less duplication). Fall back to target-level only when needed.

After every `project.pbxproj` edit, validate the file is still well-formed with `plutil -lint <project.pbxproj>` (the pbxproj is an old-style plist) before moving on. If validation fails, revert the edit and retry.

**Exception — `ENABLE_ENHANCED_SECURITY`:** Must be set at project level. If the project uses xcconfig, set it there. Otherwise, set it in the project-level `XCBuildConfiguration` blocks in `project.pbxproj`.

#### Step 1: Enhanced Security — Audit entitlements + build settings, then propose per-target diffs

Read `references/enhanced-security.md` for the full key list, defaults, deprecated keys, version migration, and the supported product-type list. For details on individual sub-options, see:
- `references/pointer-authentication.md` — arm64e pointer signing
- `references/typed-allocators.md` — type-aware memory allocation
- `references/stack-zero-init.md` — automatic stack variable zeroing
- `references/readonly-platform-memory.md` — dyld state protection
- `references/runtime-restrictions.md` — dylib and Mach message restrictions
- `references/security-compiler-warnings.md` — security-focused compiler warnings
- `references/cpp-hardening.md` — C++ stdlib hardening and bounds checking
- `references/hardware-memory-tagging.md` — ARM MTE

1. **Identify supported targets.** From the target map gathered in Phase 1 step 4, skip any target whose product type isn't in the "Supported Product Types" list in `references/enhanced-security.md`. Remaining targets are "supported targets." Note: DriverKit targets are supported for build settings only — skip entitlement changes for them.

2. **Audit each supported target.** Gather build-setting values of `ENABLE_ENHANCED_SECURITY` and `ENABLE_POINTER_AUTHENTICATION` (check target-level, then project-level inherited). For non-DriverKit targets, also read the entitlements file and collect every key under `com.apple.security.hardened-process*`, including the deprecated keys. Compare against the required + default-ON keys in `references/enhanced-security.md` Part B and bucket each target:
   - **Up-to-date** — nothing to do.
   - **Partial** — `ENABLE_ENHANCED_SECURITY` is YES, but missing default-ON sub-options, or has deprecated keys, or version `"1"` / deprecated version key present.
   - **Off** — `ENABLE_ENHANCED_SECURITY` is absent.
   - **No entitlements file** — target is supported but has no `.entitlements` file yet. If the user confirms applying, one will be created (see Step 5).

**IMPORTANT** Do not enable pointer authentication if the project has any binary dependencies (such as frameworks, xcframeworks, Swift Packages) that are not in this project from source. If the project does have such dependencies, list them and recommend that the user reach out to the vendor of the dependencies for a Universal binary that includes both arm64 and arm64e.

3. **Build the change set.** For each Partial or Off supported target, compose entitlement changes in this order (omit empty sections):
   - Add entitlements: missing required keys (`com.apple.security.hardened-process`, `...enhanced-security-version-string = "2"`) and missing default-ON sub-options (`hardened-heap`, `dyld-ro`, `platform-restrictions-string = "2"`).
   - Remove entitlements: deprecated keys (`...platform-restrictions`, `...enhanced-security-version`).
   - Update entitlements: version string `"1"` → `"2"` if present.

   If a supported target has **no `.entitlements` file**, include creating one and wiring `CODE_SIGN_ENTITLEMENTS` in the change set.

   **Build settings:** Follow "How to apply build settings" above. If the project uses xcconfig, set `ENABLE_ENHANCED_SECURITY = YES` at project level there. Otherwise, set it in the project-level `XCBuildConfiguration` blocks in `project.pbxproj`.

   Because a project-level `ENABLE_ENHANCED_SECURITY = YES` cascades `ENABLE_POINTER_AUTHENTICATION = YES` to every target, pre-write a target-level `ENABLE_POINTER_AUTHENTICATION = NO` override on each target whose platform doesn't support arm64e (detect via `SDKROOT` / `SUPPORTED_PLATFORMS`). Skip if the target already has an explicit target-level value.

   Do not auto-enable default-OFF sub-options (MTE family); report state and offer enablement in step 6 below.

4. **Present and confirm.** If every supported target is up-to-date, report that fact in one line and proceed to Step 2 (Basic Clang Safety Warnings) — do not ask an apply-confirmation when there is nothing to apply. Otherwise print the proposed list of targets to enable Enhanced Security on.

Then print a short summary of the benefits of enabling Enhanced Security in terms of the security protections it provides and code changes it may require.

   Then ask once via `AskQuestion`: "Apply the Enhanced Security changes above?" Offer "Apply all", "Apply to a subset (choose targets)", "Skip Enhanced Security".

5. **Apply.**
   - Target-level `ENABLE_POINTER_AUTHENTICATION = NO` overrides on non-arm64e-platform targets by editing the target's build configuration (xcconfig or `project.pbxproj`). Skip targets where the user already has an explicit target-level value.
   - Edit existing per-target `.entitlements` plists directly — add required + default-ON keys, remove deprecated keys, migrate version-string `"1"` → `"2"` atomically. Use `plutil` to validate edited plists.
   - For targets with no `.entitlements` file, create one and wire `CODE_SIGN_ENTITLEMENTS` to it.

   Report: "Enabled Enhanced Security on N target(s). Removed M deprecated entitlement(s). Upgraded version string to 2 on K target(s). Added arm64e override on T non-arm64e-platform target(s)."

6. **Hardware memory tagging.** Supported only for targets whose `SUPPORTED_PLATFORMS` (or `SDKROOT`) is `macosx`, `iphoneos` / `iphonesimulator`, or `xros` / `xrsimulator`. (Hardware backing is M5-class Apple silicon and later; tvOS, watchOS, and DriverKit targets are not supported.) Skip this step if Enhanced Security was not applied or if no modified target matches one of those platforms. Otherwise ask via `AskQuestion`: "Hardware memory tagging is available via `com.apple.security.hardened-process.checked-allocations`. Do you want to enable it?" If yes → read `references/hardware-memory-tagging.md` and apply it.

#### Step 2: Basic Clang Safety Warnings

For codebases with C, C++, Objective-C, and Objective-C++, apply without asking. For pure Swift codebases, skip this step. Skip settings already enabled. Unless annotated otherwise, all settings below apply to C/C++/ObjC/ObjC++.

- `GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR`
- `GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE`
- `CLANG_WARN_IMPLICIT_FALLTHROUGH = YES`
- `GCC_WARN_64_TO_32_BIT_CONVERSION = YES`
- `GCC_TREAT_IMPLICIT_FUNCTION_DECLARATIONS_AS_ERRORS = YES` (C/ObjC/ObjC++ only)
- `CLANG_ANALYZER_SECURITY_FLOATLOOPCOUNTER = YES`
- `CLANG_ANALYZER_SECURITY_INSECUREAPI_RAND = YES`
- `CLANG_ANALYZER_SECURITY_INSECUREAPI_STRCPY = YES`

Report briefly: "Enabled additional compiler warnings."

### Phase 3: Inquire about Disabled Settings

Grep pbxproj and xcconfig files for any build setting from `references/settings-and-entitlements-catalog.md` that is explicitly set to `NO`. Exclude `ENABLE_POINTER_AUTHENTICATION = NO` on targets whose platform doesn't support arm64e (the skill itself sets it there). Do flag `ENABLE_POINTER_AUTHENTICATION = NO` on arm64e-capable targets — that's a deliberate opt-out worth inquiring about. If no other disabled settings are found, skip this phase. Only consider settings relevant to the languages detected in Phase 1 — see the Scope column in the catalog.

For each disabled setting found, check whether it has an entry in the decision document with status `Disabled` and a rationale.

**If there is a documented rationale in the decision document**, note it in the report and move on. The rationale documents a prior decision that can be re-audited later.

**If there is no entry in the decision document**, ask the user:

> "I found `CLANG_ANALYZER_SECURITY_INSECUREAPI_RAND` explicitly set to NO with no explanation. Is there a reason for this?"

If the user provides a reason, accept it and record the rationale in the decision document so future audits can re-evaluate it. If no reason, recommend re-enabling.

This also applies to any setting the skill would normally enable, such as `ENABLE_ENHANCED_SECURITY`. If any is already explicitly set to NO, follow the same decision-document-check-then-inquire flow.

### Phase 4: Validate Settings

For each target modified in Phase 2, run `xcodebuild -showBuildSettings -json` to verify that every build setting applied appears with the expected value. If a setting is missing or has an unexpected value, flag it in the report as potentially unsupported by the current Xcode version. See `references/reading-build-settings.md` for the output schema and the recipe for handling large results.

### Phase 5: Report and Decision Document

Produce a lean summary:

1. **Enabled:** List project-wide settings that were enabled.
2. **Enhanced Security per target:** For each supported target, one line: target name, final status (up-to-date / applied / skipped-by-user), and a terse delta (entitlements added, deprecated keys removed, version bumps, whether an entitlements file was created). Roll up targets skipped because the product type isn't supported into a single line rather than one per target.
3. **Already active:** List settings that were already configured correctly.
4. **Inquired:** Settings that were found disabled and the outcome of the inquiry.

**Decision document.** Read `references/decision-document.md` and follow it to create or update the decision document.

### Phase 6: Optional Follow-up Steps

Offer these one at a time, in order. Each is a separate yes/no question — do not combine them into a single multi-choice prompt. For recommended adoption order and a decision matrix based on language mix, see `references/adoption-strategy.md`.

1. **Additional settings.** Ask via `AskQuestion`: "There are additional diagnostic settings that could find more issues but may also produce false positives. Want to enable them?" If yes → read `references/additional-settings.md` and follow it.

2. **Bounds safety programming models** (only if C or C++ code present). For C projects, ask: "Want to look into adopting `ENABLE_C_BOUNDS_SAFETY`? It's an annotation-based programming model for C bounds safety." For C++ projects, ask: "Want to look into adopting `ENABLE_CPLUSPLUS_BOUNDS_SAFE_BUFFERS`? It enables C++ bounds-safe buffer patterns." If yes, help the user research and plan adoption.

## User-Facing Interaction Guidelines

- **Keep replies lean.** Short sentences.
- **Keep user questions minimal.** Two scheduled questions: the Enhanced Security apply-confirmation and the hardware memory tagging offer. Other questions are situational: inquiries about deliberately-disabled settings (only when an explicit `= NO` lacks a documented rationale) and the decision document location (first creation only).
- **Report progress** so the user can track: "Enabling...", "Evaluating...", "Keeping/Reverting..."
- **Use `AskQuestion`** for inquiring about disabled settings, for the Enhanced Security apply-confirmation (including offering "apply to a subset"), and for the decision document location (first creation only).
- **When asking a question provide context the user needs to answer the question**. For example, describe the benefit of the security protection before asking whether to enable it. Describe it in terms of the protection it provides, not how it is enabled.
- **When emitting lists of Xcode build settings, use bullet lists.** Don't use comma-separated lists.
