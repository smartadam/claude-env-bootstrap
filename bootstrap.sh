#!/bin/sh
# claude-env bootstrap for macOS (Phase 1M).
#
# Run by the machine's owner in Terminal.app, never by a Claude session: it refuses when CLAUDECODE is set.
# It holds no secrets and no configuration. The two private repo URLs are arguments, so the exact command
# line lives in the private repo's docs, not here.
#
#   sh bootstrap.sh --env-repo <https URL of the env repo> --ct-repo <https URL of the CT config repo> --host <host id>
#
# What it does, in order, asking before each change:
#   1. puts ~/.local/bin on PATH in ~/.zshrc (Claude Code's native installer does not);
#   2. checks Homebrew and PRINTS the official install pointer when it is missing (you install it yourself);
#   3. offers to brew-install the missing tools: gh, node, python@3.13 (git-credential-manager when absent);
#   4. clones or fast-forwards the two repos to ~/Dev/claude-env and ~/CT/claude-config-ct (GitHub sign-ins
#      happen in your browser through Git Credential Manager);
#   5. runs the env repo's unit tests, then `envkit apply` as a dry-run, and offers --write;
#   6. prints the privileged step and the manual steps that remain.
set -eu

ENV_DIR="$HOME/Dev/claude-env"
CT_DIR="$HOME/CT/claude-config-ct"
ENV_REPO=""
CT_REPO=""
HOST_ID=""

die() { printf 'bootstrap: %s\n' "$1" >&2; exit "${2:-1}"; }
say() { printf '\n== %s\n' "$1"; }
ask() {
  printf '%s [y/N] ' "$1"
  read -r reply
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --env-repo) ENV_REPO="${2:-}"; shift 2 ;;
    --ct-repo) CT_REPO="${2:-}"; shift 2 ;;
    --host) HOST_ID="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "${CLAUDECODE:-}" ] && die "refused: run this in Terminal.app yourself, not inside a Claude Code session" 3
[ "$(uname -s)" = "Darwin" ] || die "this script is for macOS; Windows uses bootstrap.ps1"
{ [ -n "$ENV_REPO" ] && [ -n "$CT_REPO" ] && [ -n "$HOST_ID" ]; } || die "need --env-repo, --ct-repo and --host (see the env repo's docs)"
[ -t 0 ] || die "needs an interactive terminal"

say "1. PATH"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) echo "~/.local/bin is on PATH" ;;
  *)
    if ask "Add ~/.local/bin to PATH in ~/.zshrc?"; then
      printf '\n# Claude Code native install (claude-env bootstrap)\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"
      PATH="$HOME/.local/bin:$PATH"; export PATH
      echo "added; new terminals pick it up"
    fi ;;
esac
if command -v claude >/dev/null 2>&1; then
  echo "claude: $(claude --version 2>/dev/null)"
else
  echo "claude: not found (install Claude Code first: https://code.claude.com/docs)"
fi

say "2. Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then eval "$("$b" shellenv)"; fi
  done
fi
if command -v brew >/dev/null 2>&1; then
  echo "brew: $(brew --version | head -1)"
else
  echo "Homebrew is not installed. Install it yourself from https://brew.sh (it asks for your password), then re-run this script."
  echo "On a managed Mac, check with IT first if installs are restricted."
  exit 0
fi

say "3. Tools"
missing=""
command -v gh >/dev/null 2>&1 || missing="$missing gh"
command -v node >/dev/null 2>&1 || missing="$missing node"
brew list --versions python@3.13 >/dev/null 2>&1 || missing="$missing python@3.13"
for t in $missing; do echo "missing: $t"; done
if [ -n "$missing" ] && ask "brew install$missing ?"; then
  # shellcheck disable=SC2086
  brew install $missing
fi
if ! git credential-manager --version >/dev/null 2>&1; then
  echo "missing: git-credential-manager"
  if ask "brew install --cask git-credential-manager ?"; then brew install --cask git-credential-manager; fi
fi
PY="$(brew --prefix python@3.13 2>/dev/null || true)/bin/python3.13"
[ -x "$PY" ] || PY="$(command -v python3)"
echo "python for envkit: $PY ($("$PY" -V 2>&1))"

say "4. Repos"
clone_or_pull() {
  url="$1"; dir="$2"
  if [ -d "$dir/.git" ]; then
    echo "$dir: fast-forward"
    git -C "$dir" pull --ff-only
  elif ask "Clone $url to $dir ? (a browser sign-in may open)"; then
    mkdir -p "$(dirname "$dir")"
    git clone "$url" "$dir"
  fi
}
clone_or_pull "$ENV_REPO" "$ENV_DIR"
clone_or_pull "$CT_REPO" "$CT_DIR"
[ -f "$ENV_DIR/envkit.py" ] || die "env repo not present at $ENV_DIR"

say "5. Tests and apply"
(cd "$ENV_DIR" && "$PY" -m unittest discover -s tests) || die "envkit tests failed; stop and report the output"
(cd "$ENV_DIR" && "$PY" envkit.py apply --host "$HOST_ID" --ct-root "$CT_DIR")
if ask "Apply the ordinary layer now (--write; it backs up what it replaces)?"; then
  (cd "$ENV_DIR" && "$PY" envkit.py apply --host "$HOST_ID" --ct-root "$CT_DIR" --write)
fi

say "6. What is left (yours)"
cat <<EOF
- Privileged settings (permissions, plugins, the mods' plugin dirs). Read the dry-run above, then run:
    cd "$ENV_DIR" && "$PY" envkit.py apply --host "$HOST_ID" --ct-root "$CT_DIR" --privileged
  It asks you to type APPLY PRIVILEGED and refuses inside Claude Code.
- OneDrive (personal): turn on selective sync for Documents/Claude/Projects/AI Offerings only, then send the
  folder's full path to the PC session so it can fill CT_AI_OFFERINGS_ROOT in machines.json.
- Restart Claude Code, open a session in Terminal.app and run /status and /skills to confirm.
EOF
