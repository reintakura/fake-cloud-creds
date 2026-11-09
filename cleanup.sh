#!/usr/bin/env bash
# cleanup.sh — remove only files listed in .advsim-manifest-* under a target.
# Verifies ADVSIM-DUMMY marker before deleting each file.
# Compatible with macOS Bash 3.2 and Linux Bash.
set -euo pipefail

MARKER="ADVSIM-DUMMY"

if [ "$(id -u)" -eq 0 ]; then
  echo "error: refusing to run as root. Run as a normal user." >&2
  exit 1
fi

TARGET=""
DRY_RUN=0
ALL=0
MANIFEST_ARG=""

usage() {
  cat <<'EOF'
Usage: cleanup.sh [options]

Remove only files created by gen-creds.sh, using its manifests.

Options:
  --target DIR       Root that holds .advsim-manifest-* (default: ./decoy-home)
  --manifest FILE    Clean using only this one manifest
  --all              Process every .advsim-manifest-* under --target
  --dry-run          Show what would be removed; delete nothing
  -h, --help         Show this help

Behaviour:
  - Reads each manifest line.
  - Regular paths: delete the file only if it still contains ADVSIM-DUMMY.
  - Lines starting with APPEND_AWS_PROFILE:path:profile  → strip that
    [profile] block from the credentials file (with a .bak backup), only if
    the block carries the ADVSIM-DUMMY marker.
  - Empty directories left behind are removed when safe.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || { echo "error: --target needs a value" >&2; exit 2; }
      TARGET=$2; shift 2 ;;
    --manifest)
      [ $# -ge 2 ] || { echo "error: --manifest needs a value" >&2; exit 2; }
      MANIFEST_ARG=$2; shift 2 ;;
    --all) ALL=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="./decoy-home"
fi

case "$TARGET" in
  /*) ;;
  *) TARGET="$(pwd)/$TARGET" ;;
esac
TARGET=$(printf '%s' "$TARGET" | sed 's|/\./|/|g')

if [ ! -d "$TARGET" ]; then
  echo "error: target does not exist: $TARGET" >&2
  exit 1
fi

# Collect manifests into a newline list (no mapfile / no arrays-of-arrays)
MANIFEST_LIST=""
if [ -n "$MANIFEST_ARG" ]; then
  if [ ! -f "$MANIFEST_ARG" ]; then
    echo "error: manifest not found: $MANIFEST_ARG" >&2
    exit 1
  fi
  MANIFEST_LIST=$MANIFEST_ARG
else
  # Default: newest one; --all: every match. Use ls -1 (portable).
  # shellcheck disable=SC2012
  found=$(ls -1 "$TARGET"/.advsim-manifest-* 2>/dev/null || true)
  if [ -z "$found" ]; then
    echo "error: no .advsim-manifest-* under $TARGET" >&2
    exit 1
  fi
  if [ "$ALL" -eq 1 ]; then
    MANIFEST_LIST=$found
  else
    # pick the last (lexicographically latest timestamped name)
    MANIFEST_LIST=$(printf '%s\n' "$found" | sort | tail -n 1)
  fi
fi

echo "cleanup target : $TARGET"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "mode           : dry-run"
fi
echo

file_has_marker() {
  # $1 = path. Return 0 if ADVSIM-DUMMY present.
  grep -q "$MARKER" "$1" 2>/dev/null
}

strip_aws_profile() {
  # $1=creds_path  $2=profile_name
  _creds=$1
  _prof=$2
  if [ ! -f "$_creds" ]; then
    echo "  skip (missing): $_creds"
    return 0
  fi
  if ! file_has_marker "$_creds"; then
    echo "warn: refuse to edit (no $MARKER): $_creds" >&2
    return 1
  fi
  if ! grep -q "^\[$_prof\]" "$_creds"; then
    echo "  skip (profile gone): [$_prof] in $_creds"
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] strip profile [$_prof] from $_creds"
    return 0
  fi

  _bak="${_creds}.bak.advsim"
  cp "$_creds" "$_bak"
  # Drop the [profile] section through the next [section] or EOF.
  # Marker comment lives INSIDE the section (see gen-creds.sh --append).
  awk -v p="$_prof" '
    BEGIN { skip=0 }
    /^\[/ {
      if ($0 == "[" p "]") { skip=1; next }
      skip=0
    }
    skip { next }
    { print }
  ' "$_bak" > "$_creds"
  echo "  ~ stripped [$_prof] from $_creds (backup: $_bak)"
}

remove_file() {
  _f=$1
  if [ ! -e "$_f" ]; then
    echo "  skip (missing): $_f"
    return 0
  fi
  if ! file_has_marker "$_f"; then
    echo "warn: refuse to delete (no $MARKER): $_f" >&2
    return 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] rm $_f"
    return 0
  fi
  rm -f "$_f"
  echo "  - $_f"
}

process_manifest() {
  _m=$1
  echo "==> manifest: $_m"
  # Read line by line (Bash 3.2)
  while IFS= read -r line || [ -n "$line" ]; do
    # skip blank / comment
    case "$line" in
      ''|\#*) continue ;;
    esac
    case "$line" in
      APPEND_AWS_PROFILE:*)
        # APPEND_AWS_PROFILE:path:profile
        rest=${line#APPEND_AWS_PROFILE:}
        # Split on last colon for profile (path may theoretically contain :)
        # Profile names we generate never contain ':', so split on first ':' after path is hard;
        # our generator writes absolute paths without colons on Unix. Split: path=everything
        # before last ':', profile=after last ':'.
        path=${rest%:*}
        prof=${rest##*:}
        strip_aws_profile "$path" "$prof" || true
        ;;
      *)
        remove_file "$line" || true
        ;;
    esac
  done < "$_m"

  if [ "$DRY_RUN" -eq 0 ]; then
    rm -f "$_m"
    echo "  - $_m (manifest consumed)"
  else
    echo "  [dry-run] would remove manifest $_m"
  fi
  echo
}

# Process each manifest
printf '%s\n' "$MANIFEST_LIST" | while IFS= read -r m || [ -n "$m" ]; do
  [ -n "$m" ] || continue
  process_manifest "$m"
done

# Best-effort: remove empty decoy dirs (deepest first). Never touch non-empty.
if [ "$DRY_RUN" -eq 0 ]; then
  # Common decoy subdirs
  for d in \
    "$TARGET/.aws" \
    "$TARGET/.config/gcloud" \
    "$TARGET/.config/doctl" \
    "$TARGET/.config/heroku" \
    "$TARGET/.config" \
    "$TARGET/.azure" \
    "$TARGET/.kube" \
    "$TARGET/.docker"
  do
    if [ -d "$d" ]; then
      rmdir "$d" 2>/dev/null && echo "  removed empty dir: $d" || true
    fi
  done
fi

echo "cleanup done."
