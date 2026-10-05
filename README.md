# claude-env-bootstrap

Public entry point for rebuilding a Claude Code environment. It holds no secrets and no configuration: the private
repo URLs and the host id are arguments, and the exact command line lives in the private env repo's docs.

The bootstrap scripts are run only by a pinned command that downloads them at a fixed commit and checks their
SHA-256 before running them. This README is informational, not authoritative.

| Script | Status |
|---|---|
| `bootstrap.sh` (macOS) | Phase 1M. Run by the machine's owner in Terminal.app; refuses inside a Claude Code session. Asks before every change, points to (never runs) the Homebrew install, clones the two private repos, runs the env repo's tests and `envkit apply` as a dry-run, then offers `--write`. Privileged settings stay a separate step the owner runs. |
| `bootstrap.ps1` (Windows) | Placeholder until Phase 1. |

Pinned run (take the commit and its SHA-256 from the private docs):

```sh
curl -fsSL -o /tmp/bootstrap.sh https://raw.githubusercontent.com/<owner>/claude-env-bootstrap/<commit>/bootstrap.sh
shasum -a 256 /tmp/bootstrap.sh   # must equal the recorded SHA-256
sh /tmp/bootstrap.sh --env-repo <url> --ct-repo <url> --host <id>
```
