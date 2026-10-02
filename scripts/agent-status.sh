#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Gemeinsamer Live-Status für Codex und Claude über lokale Git-Referenzen.

Verwendung:
  ./scripts/agent-status.sh list
  ./scripts/agent-status.sh show <codex|claude>
  ./scripts/agent-status.sh claim <codex|claude> "Aufgabe" [Datei ...]
  ./scripts/agent-status.sh progress <codex|claude> "Zwischenstand"
  ./scripts/agent-status.sh done <codex|claude> "Ergebnis"

Bei claim müssen betroffene Dateien als relative, genaue Pfade angegeben werden.
Ist eine Datei bereits vom anderen Agenten reserviert, endet der Befehl mit Fehler 2.
USAGE
}

repository_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repository_root" ]]; then
  echo "FEHLER: Agent-Status benötigt ein Git-Repository." >&2
  exit 1
fi
cd "$repository_root"

agent_ref() {
  case "$1" in
    codex|claude) printf 'refs/ai-status/%s' "$1" ;;
    *)
      echo "FEHLER: Agent muss codex oder claude sein." >&2
      exit 1
      ;;
  esac
}

agent_label() {
  case "$1" in
    codex) printf 'Codex' ;;
    claude) printf 'Claude' ;;
  esac
}

other_agent() {
  case "$1" in
    codex) printf 'claude' ;;
    claude) printf 'codex' ;;
  esac
}

read_status() {
  local ref object_id
  ref="$(agent_ref "$1")"
  object_id="$(git rev-parse --verify -q "$ref" || true)"
  [[ -n "$object_id" ]] || return 1
  git cat-file blob "$object_id"
}

field_from_status() {
  local field="$1"
  awk -v prefix="$field: " 'index($0, prefix) == 1 { sub(prefix, ""); print; exit }'
}

write_status() {
  local agent="$1"
  local state="$2"
  local task="$3"
  local note="$4"
  local file_lines="$5"
  local branch commit object_id payload

  branch="$(git branch --show-current)"
  [[ -n "$branch" ]] || branch="DETACHED"
  commit="$(git rev-parse --short HEAD)"
  payload="$({
    printf 'Agent: %s\n' "$(agent_label "$agent")"
    printf 'Status: %s\n' "$state"
    printf 'Updated: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf 'Branch: %s\n' "$branch"
    printf 'Commit: %s\n' "$commit"
    printf 'Worktree: %s\n' "$repository_root"
    printf 'Task: %s\n' "$task"
    [[ -n "$file_lines" ]] && printf '%s\n' "$file_lines"
    printf 'Note: %s\n' "$note"
  })"
  object_id="$(printf '%s\n' "$payload" | git hash-object -w --stdin)"
  git update-ref "$(agent_ref "$agent")" "$object_id"
  printf '%s\n' "$payload"
}

normalize_file() {
  local file="${1#./}"
  case "$file" in
    ""|/*|..|../*|*/..|*/../*)
      echo "FEHLER: Nur genaue relative Projektpfade sind erlaubt: $1" >&2
      exit 1
      ;;
  esac
  printf '%s' "$file"
}

command_name="${1:-list}"
case "$command_name" in
  list)
    for agent in codex claude; do
      printf '%s\n' "--- $(agent_label "$agent") ---"
      read_status "$agent" || printf 'Kein Status vorhanden.\n'
    done
    ;;

  show)
    [[ $# -eq 2 ]] || { usage >&2; exit 1; }
    agent_ref "$2" >/dev/null
    read_status "$2" || printf 'Kein Status für %s vorhanden.\n' "$(agent_label "$2")"
    ;;

  claim)
    [[ $# -ge 3 ]] || { usage >&2; exit 1; }
    agent="$2"
    task="$3"
    shift 3
    agent_ref "$agent" >/dev/null
    peer="$(other_agent "$agent")"
    peer_status="$(read_status "$peer" || true)"
    peer_state="$(printf '%s\n' "$peer_status" | field_from_status Status)"
    file_lines=""

    for supplied_file in "$@"; do
      file="$(normalize_file "$supplied_file")"
      if [[ "$peer_state" == "WORKING" ]] && printf '%s\n' "$peer_status" | rg --fixed-strings --line-regexp --quiet "File: $file"; then
        echo "KONFLIKT: $(agent_label "$peer") arbeitet bereits an $file" >&2
        echo "Erst Status abstimmen oder unterschiedliche Dateien wählen." >&2
        exit 2
      fi
      if [[ -n "$file_lines" ]]; then
        file_lines+=$'\n'
      fi
      file_lines+="File: $file"
    done

    write_status "$agent" WORKING "$task" "Aufgabe und Dateibereich reserviert." "$file_lines"
    ;;

  progress)
    [[ $# -eq 3 ]] || { usage >&2; exit 1; }
    agent="$2"
    current="$(read_status "$agent" || true)"
    [[ -n "$current" ]] || { echo "FEHLER: Erst claim ausführen." >&2; exit 1; }
    task="$(printf '%s\n' "$current" | field_from_status Task)"
    file_lines="$(printf '%s\n' "$current" | rg '^File: ' || true)"
    write_status "$agent" WORKING "$task" "$3" "$file_lines"
    ;;

  done)
    [[ $# -eq 3 ]] || { usage >&2; exit 1; }
    agent="$2"
    current="$(read_status "$agent" || true)"
    task="$(printf '%s\n' "$current" | field_from_status Task)"
    [[ -n "$task" ]] || task="Keine aktive Aufgabe"
    write_status "$agent" DONE "$task" "$3" ""
    ;;

  help|-h|--help)
    usage
    ;;

  *)
    usage >&2
    exit 1
    ;;
esac
