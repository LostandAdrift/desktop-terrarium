# Desktop Terrarium development

This is an Omarchy Quattro plugin, not a website or an independent desktop shell.

- The user wants a surprise reveal. Never show previews or describe the appearance in progress messages. Technical progress and blockers are fine.
- Work only in this repository unless the coordinating agent explicitly assigns a testing directory. Never modify packaged Omarchy files under /usr/share/omarchy.
- Native integration belongs inside the existing Omarchy shell. Test harnesses may render plain QtQuick components offscreen.
- Runtime dependencies: Python standard library, QtQuick and Quickshell already on Omarchy. No network calls or cloud dependency at runtime.
- Read-only telemetry. Never terminate processes or alter system performance, device settings, or process priorities.
- Collect only aggregate system counters and process executable names/numeric usage. Do not collect command lines, window titles, file contents, browser URLs, or credentials.
- Bound resource use and data retention. Suspend scene animation when hidden and support reduced motion. Treat process disappearance as disappearance, never as verified successful completion.
- Keep UI data separate from the renderer. Put deterministic state and math in pure JavaScript functions with meaningful tests. Python collector must be tested against fake procfs fixtures.
- Use process argument arrays, never interpolate data into shell commands. Render external names as plain text.
- Tests must cover behavior and edge cases, not merely repeat the implementation. Test native lifecycle, keyboard controls, scaling, disable/re-enable, and removal before release.
- Do not commit credentials, session transcripts, local machine snapshots, or private paths. Only synthetic telemetry fixtures belong in git.
- Grok implementation agents must use the user's existing OAuth session with model grok-4.6. Do not fall back to paid API credentials, purchase credits, or change authentication configuration.
- Follow the scope of your assigned files. Leave git operations and desktop installation to the coordinating agent.
