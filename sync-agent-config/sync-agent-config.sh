#!/bin/bash
set -eu -o pipefail

REPO_ROOT="${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel)}"
cd "$REPO_ROOT"

fail() {
  echo "sync-agent-config: $1" >&2
  exit 1
}

print_body() {
  awk 'NR==1 && /^---$/ {in_fm=1; next} in_fm && /^---$/ {in_fm=0; next} !in_fm' "$1" | sed -e '/[^[:space:]]/,$!d'
}

# --- 1. Project-wide instructions: .github/copilot-instructions.md -> AGENTS.md ---
sync_project_wide() {
  local src=".github/copilot-instructions.md"
  local dest="AGENTS.md"

  [[ -f "$src" ]] || fail "$src not found"

  mkdir -p "$(dirname "$dest")"
  {
    echo "<!-- DO NOT EDIT: Generated mirror of /$src. Edit /$src instead. -->"
    echo ""
    cat "$src"
  } > "$dest"

  echo "sync-agent-config: synced $dest"
}

# --- 2. Path-specific instructions: .github/instructions -> .claude/rules ---
sync_path_specific() {
  local src_dir=".github/instructions"
  local dest_dir=".claude/rules"

  rm -rf "$dest_dir"
  [[ -d "$src_dir" ]] || return 0
  mkdir -p "$dest_dir"

  while IFS= read -r -d "" src; do
    local base
    base="$(basename "$src" .instructions.md)"
    local dest="$dest_dir/$base.md"
    local rel_src="${src#./}"

    local apply_to
    apply_to="$(grep -m 1 -E '^applyTo:' "$src" | sed -E 's/^applyTo:[[:space:]]*"([^"]*)".*$/\1/' || true)"

    {
      if [[ -n "$apply_to" ]]; then
        echo "---"
        echo "paths:"
        IFS="," read -ra GLOBS <<< "$apply_to"
        for glob in "${GLOBS[@]}"; do
          glob="$(echo "$glob" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
          [[ -n "$glob" ]] && echo "  - \"$glob\""
        done
        echo "---"
        echo ""
      fi
      echo "<!-- DO NOT EDIT: Generated from /$rel_src. Edit /$rel_src instead. -->"
      echo ""
      print_body "$src"
    } > "$dest"

    echo "sync-agent-config: synced $dest"
  done < <(find "$src_dir" -maxdepth 1 -name "*.instructions.md" -print0)
}

# --- 3. Skills: .agents/skills -> .claude/skills ---
sync_skills() {
  local src_dir=".agents/skills"
  local dest_dir=".claude/skills"

  rm -rf "$dest_dir"
  [[ -d "$src_dir" ]] || return 0
  mkdir -p "$dest_dir"

  while IFS= read -r -d "" src_skill; do
    local name
    name="$(basename "$src_skill")"
    local dest_skill="$dest_dir/$name"

    # Symlinks must stay inside the canonical skills directory.
    while IFS= read -r -d "" link; do
      target="$(realpath -m "$link")"
      case "$target" in
        "$REPO_ROOT/$src_dir/"*) ;;
        *) fail "symlink escapes $src_dir: $link" ;;
      esac
    done < <(find "$src_skill" -type l -print0)

    # Archive mode preserves symlinks and file modes.
    cp -a "$src_skill" "$dest_skill"

    if [[ -f "$src_skill/SKILL.md" && ! -L "$dest_skill/SKILL.md" ]]; then
      {
        if [[ "$(head -n 1 "$src_skill/SKILL.md")" == "---" ]]; then
          awk 'NR==1 {in_fm=1; print; next} in_fm {print; if (/^---$/) exit}' "$src_skill/SKILL.md"
          echo ""
        fi
        echo "<!-- DO NOT EDIT: Generated from /$src_dir/$name. Edit /$src_dir/$name instead. -->"
        echo ""
        print_body "$src_skill/SKILL.md"
      } > "$dest_skill/SKILL.md"
    fi

    echo "sync-agent-config: synced $dest_skill"
  done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type d -print0)
}

sync_project_wide
sync_path_specific
sync_skills
