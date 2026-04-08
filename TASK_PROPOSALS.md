# Codebase task proposals

## 1) Typo fix task
**Title:** Fix repository slug typo in `GITHUB_CMD`

- **Issue found:** `GITHUB_CMD` points to `xray-vless-reality-livefree` instead of `xray-vless-reality-nokey`.
- **Why this is a typo:** The canonical repository URL constant in the same script is `xray-vless-reality-nokey`, so the alias command string appears to contain a mistaken repo name.
- **Impact:** Users who rely on the `nokey` alias may fetch a script from the wrong path/repository.
- **Acceptance criteria:**
  - Update `GITHUB_CMD` to use the `xray-vless-reality-nokey` path.
  - Verify `alias_line` resolves to the same repo as `GITHUB_URL`.

## 2) Bug fix task
**Title:** Fix `--netstack` IP initialization order bug

- **Issue found:** `parse_args` runs before `detect_network_interfaces`. When users pass `--netstack=4` or `--netstack=6`, `ip` is set from `IPv4/IPv6` before those values are detected.
- **Impact:** `ip` can remain empty in later output/share links, producing invalid connection strings.
- **Acceptance criteria:**
  - Ensure IP selection occurs after interface detection (or re-resolve `ip` during `initialize_variables` whenever `netstack` is set).
  - Add a regression test proving `--netstack=4|6` yields a non-empty `ip` when corresponding public IP exists.

## 3) Documentation discrepancy task
**Title:** Align uninstall instructions across READMEs

- **Issue found:** `README.md` documents uninstall via this script (`nokey.sh ... --remove`), but `README.en.md`/`README.fa.md` show direct Xray installer uninstall command.
- **Impact:** Inconsistent user guidance; non-Chinese readers may miss NoKey cleanup behavior (alias removal + wrapper flow).
- **Acceptance criteria:**
  - Standardize uninstall guidance across all three READMEs.
  - Explicitly document the recommended uninstall path and any differences between "remove Xray only" vs "remove NoKey alias + Xray".

## 4) Test improvement task
**Title:** Add shell-level regression tests for argument and output generation flow

- **Issue found:** Repository lacks automated tests for critical argument/config generation behavior.
- **Proposed focus:**
  - Validate `--netstack`, `--port`, and `--domain` argument interactions.
  - Validate generated share links are well-formed for IPv4 and IPv6.
  - Validate alias command template points to expected repository path.
- **Acceptance criteria:**
  - Add a lightweight shell test harness (e.g., `bats`) that can run in CI.
  - Include at least one failing regression case from the current behavior, then make it pass with the fix.
