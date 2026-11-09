#!/usr/bin/env bash
# gen-creds.sh — generate DUMMY (non-functional) cloud credentials for
# authorized adversary-simulation / purple-team decoy & honeytoken work.
# Compatible with macOS Bash 3.2 and Linux Bash.
# Every generated artifact contains the marker ADVSIM-DUMMY and a run id.
set -euo pipefail

VERSION="1.0.0"
MARKER="ADVSIM-DUMMY"

# ---------------------------------------------------------------------------
# Safety: never run as root
# ---------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
  echo "error: refusing to run as root. Run as a normal user." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
TARGET=""
ONLY="aws,gcp,azure,other"
PROFILE="advsim"
PROJECT="advsim-dummy-project"
DRY_RUN=0
APPEND=0
RUN_ID=""

usage() {
  cat <<'EOF'
Usage: gen-creds.sh [options]

Generate DUMMY (non-functional) cloud credentials as decoy/honeytoken files.
macOS Bash 3.2 + Linux Bash. No sudo. Requires only bash + coreutils
(openssl optional for a throwaway RSA private key in the GCP SA JSON).

Options:
  --target DIR       Output root (default: ./decoy-home). Mirrors $HOME layout.
  --only LIST        Comma-separated: aws,gcp,azure,other (default: all)
  --profile NAME     AWS profile base name (default: advsim)
  --project ID       GCP project_id (default: advsim-dummy-project)
  --append           For ~/.aws/credentials only: append [advsim-<id>] if file exists
  --dry-run          Print what would be written; create nothing
  -h, --help         Show this help
  -v, --version      Show version

Environment (optional canary tokens):
  AWS_CANARY_KEY_ID   If set, use as AWS Access Key Id instead of random
  AWS_CANARY_SECRET   If set, use as AWS Secret Access Key instead of random
  Tip: mint a canary at https://canarytokens.org/ and drop the values here so
  any use of the decoy key triggers an alert.

Safety:
  - Never overwrites an existing file (skip + warn). Use --append only for
    AWS credentials profiles.
  - Every file embeds ADVSIM-DUMMY + a run id.
  - Default target is ./decoy-home, not $HOME. Pass --target "$HOME" only on
    a dedicated decoy host you control.
  - Refuse to run as root.
EOF
}

# ---------------------------------------------------------------------------
# Arg parse (Bash 3.2 safe)
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || { echo "error: --target needs a value" >&2; exit 2; }
      TARGET=$2; shift 2 ;;
    --only)
      [ $# -ge 2 ] || { echo "error: --only needs a value" >&2; exit 2; }
      ONLY=$2; shift 2 ;;
    --profile)
      [ $# -ge 2 ] || { echo "error: --profile needs a value" >&2; exit 2; }
      PROFILE=$2; shift 2 ;;
    --project)
      [ $# -ge 2 ] || { echo "error: --project needs a value" >&2; exit 2; }
      PROJECT=$2; shift 2 ;;
    --append) APPEND=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -v|--version) echo "gen-creds.sh $VERSION"; exit 0 ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="./decoy-home"
fi

# Resolve to absolute-ish path without readlink -f (macOS-safe)
case "$TARGET" in
  /*) ;;
  *) TARGET="$(pwd)/$TARGET" ;;
esac
# Collapse /./ segments (portable, no readlink -f)
TARGET=$(printf '%s' "$TARGET" | sed 's|/\./|/|g')

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
rand_alnum() {
  # $1 = length. Upper+lower+digits.
  # head closes early → tr SIGPIPE (141); ignore under pipefail.
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1" || true
}

rand_upper() {
  LC_ALL=C tr -dc 'A-Z0-9' </dev/urandom | head -c "$1" || true
}

rand_hex() {
  LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c "$1" || true
}

rand_base64ish() {
  # 40-char AWS-secret-looking string (A-Za-z0-9+/)
  LC_ALL=C tr -dc 'A-Za-z0-9+/' </dev/urandom | head -c "$1" || true
}

rand_guid() {
  # UUID-ish: 8-4-4-4-12 lowercase hex
  printf '%s-%s-%s-%s-%s' \
    "$(rand_hex 8)" "$(rand_hex 4)" "$(rand_hex 4)" "$(rand_hex 4)" "$(rand_hex 12)"
}

# lowercase via tr (no ${var,,})
to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# comma-list contains token?
list_has() {
  # $1=list $2=token
  printf ',%s,' "$1" | tr '[:upper:]' '[:lower:]' | grep -q ",$(to_lower "$2"),"
}

ensure_dir() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] mkdir -p $1"
    return 0
  fi
  mkdir -p "$1"
}

# Write file unless it exists. Args: path, then content via stdin.
# Returns 0 if written, 1 if skipped.
write_new() {
  _path=$1
  if [ -e "$_path" ]; then
    echo "warn: skip (exists): $_path" >&2
    return 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] write $_path"
    # Drain stdin so callers don't break
    cat >/dev/null
    return 0
  fi
  ensure_dir "$(dirname "$_path")"
  cat > "$_path"
  chmod 600 "$_path" 2>/dev/null || true
  echo "$_path" >> "$MANIFEST"
  echo "  + $_path"
  return 0
}

# Append a line to manifest for an existing file we modified (append mode)
manifest_note() {
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  echo "$1" >> "$MANIFEST"
}

# ---------------------------------------------------------------------------
# Run id + target prep
# ---------------------------------------------------------------------------
RUN_ID="$(date +%Y%m%d%H%M%S)-$(rand_hex 6)"
MANIFEST="$TARGET/.advsim-manifest-$RUN_ID"

echo "fake-cloud-creds $VERSION"
echo "run id : $RUN_ID"
echo "target : $TARGET"
echo "only   : $ONLY"
echo "marker : $MARKER"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "mode   : dry-run"
fi
echo

if [ "$DRY_RUN" -eq 0 ]; then
  ensure_dir "$TARGET"
  {
    echo "# ADVSIM-DUMMY manifest"
    echo "# run_id=$RUN_ID"
    echo "# created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# target=$TARGET"
    echo "# Do NOT edit by hand unless you know what you are doing."
    echo "# cleanup.sh reads this file to remove only what this run created."
  } > "$MANIFEST"
fi

# ---------------------------------------------------------------------------
# AWS
# ---------------------------------------------------------------------------
gen_aws() {
  echo "==> AWS"
  aws_dir="$TARGET/.aws"
  ensure_dir "$aws_dir"

  if [ -n "${AWS_CANARY_KEY_ID:-}" ]; then
    akid="$AWS_CANARY_KEY_ID"
    echo "  using AWS_CANARY_KEY_ID from environment"
  else
    akid="AKIA$(rand_upper 16)"
  fi
  if [ -n "${AWS_CANARY_SECRET:-}" ]; then
    asec="$AWS_CANARY_SECRET"
    echo "  using AWS_CANARY_SECRET from environment"
  else
    asec="$(rand_base64ish 40)"
  fi

  region="ap-southeast-1"
  profile_name="${PROFILE}-${RUN_ID}"

  creds_path="$aws_dir/credentials"
  conf_path="$aws_dir/config"

  # credentials
  if [ -e "$creds_path" ]; then
    if [ "$APPEND" -eq 1 ]; then
      echo "  append profile [$profile_name] to $creds_path"
      if [ "$DRY_RUN" -eq 0 ]; then
        {
          echo ""
          echo "[$profile_name]"
          echo "# $MARKER run_id=$RUN_ID"
          echo "aws_access_key_id = $akid"
          echo "aws_secret_access_key = $asec"
          echo "advsim_marker = $MARKER"
          echo "advsim_run_id = $RUN_ID"
        } >> "$creds_path"
        # Record append action specially so cleanup can strip the profile
        echo "APPEND_AWS_PROFILE:$creds_path:$profile_name" >> "$MANIFEST"
      fi
    else
      echo "warn: skip (exists): $creds_path  (pass --append to add a profile)" >&2
    fi
  else
    write_new "$creds_path" <<EOF
# $MARKER run_id=$RUN_ID
# DUMMY credentials for authorized adversary simulation. Not a real AWS key.
[default]
aws_access_key_id = $akid
aws_secret_access_key = $asec
advsim_marker = $MARKER
advsim_run_id = $RUN_ID

[$profile_name]
aws_access_key_id = $akid
aws_secret_access_key = $asec
advsim_marker = $MARKER
advsim_run_id = $RUN_ID
EOF
  fi

  # config
  write_new "$conf_path" <<EOF
# $MARKER run_id=$RUN_ID
# DUMMY AWS config for authorized adversary simulation.
[default]
region = $region
output = json
# advsim_marker = $MARKER

[profile $profile_name]
region = $region
output = json
EOF
}

# ---------------------------------------------------------------------------
# GCP
# ---------------------------------------------------------------------------
gen_gcp_private_key_pem() {
  # Produce a PEM private key body. Prefer openssl RSA; else random-looking PEM.
  if command -v openssl >/dev/null 2>&1; then
    # 2048-bit throwaway key; discard to a temp then re-read (macOS mktemp ok)
    _tmp=$(mktemp "${TMPDIR:-/tmp}/advsim-key.XXXXXX")
    if openssl genrsa -out "$_tmp" 2048 >/dev/null 2>&1; then
      cat "$_tmp"
      rm -f "$_tmp"
      return 0
    fi
    rm -f "$_tmp"
  fi
  # Fallback: syntactically PEM-shaped but not a valid RSA key
  echo "-----BEGIN RSA PRIVATE KEY-----"
  # 28 lines of base64-ish
  i=0
  while [ $i -lt 28 ]; do
    LC_ALL=C tr -dc 'A-Za-z0-9+/' </dev/urandom | head -c 64 || true
    echo
    i=$((i + 1))
  done
  echo "-----END RSA PRIVATE KEY-----"
}

gen_gcp() {
  echo "==> GCP"
  gcloud_dir="$TARGET/.config/gcloud"
  ensure_dir "$gcloud_dir"

  pk_id="$(rand_hex 40)"
  client_id="$(rand_hex 21)"
  sa_name="advsim-decoy-$(rand_hex 6)"
  client_email="${sa_name}@${PROJECT}.iam.gserviceaccount.com"

  # Build PEM and escape newlines as \n for JSON
  pem_raw=$(gen_gcp_private_key_pem)
  # Convert real newlines to \n sequences for JSON string
  pem_json=$(printf '%s' "$pem_raw" | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); printf "%s\\n", $0}')

  sa_path="$gcloud_dir/advsim-sa-${RUN_ID}.json"
  write_new "$sa_path" <<EOF
{
  "_advsim": "$MARKER",
  "_advsim_run_id": "$RUN_ID",
  "_comment": "DUMMY service account for authorized adversary simulation. Not a real GCP key.",
  "type": "service_account",
  "project_id": "$PROJECT",
  "private_key_id": "$pk_id",
  "private_key": "$pem_json",
  "client_email": "$client_email",
  "client_id": "$client_id",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/$(printf '%s' "$client_email" | sed 's/@/%40/g')",
  "universe_domain": "googleapis.com"
}
EOF

  # application_default_credentials.json (user ADC style)
  adc_path="$gcloud_dir/application_default_credentials.json"
  write_new "$adc_path" <<EOF
{
  "_advsim": "$MARKER",
  "_advsim_run_id": "$RUN_ID",
  "_comment": "DUMMY ADC for authorized adversary simulation.",
  "account": "",
  "client_id": "$(rand_hex 12)-$(rand_hex 32).apps.googleusercontent.com",
  "client_secret": "$(rand_alnum 24)",
  "quota_project_id": "$PROJECT",
  "refresh_token": "1//$MARKER-$(rand_alnum 64)",
  "type": "authorized_user",
  "universe_domain": "googleapis.com"
}
EOF
}

# ---------------------------------------------------------------------------
# Azure
# ---------------------------------------------------------------------------
gen_azure() {
  echo "==> Azure"
  az_dir="$TARGET/.azure"
  ensure_dir "$az_dir"

  sub_id="$(rand_guid)"
  tenant_id="$(rand_guid)"
  client_id="$(rand_guid)"
  client_secret="$(rand_alnum 40)"
  user_name="advsim.decoy@example.com"

  profile_path="$az_dir/azureProfile.json"
  write_new "$profile_path" <<EOF
{
  "_advsim": "$MARKER",
  "_advsim_run_id": "$RUN_ID",
  "_comment": "DUMMY azureProfile for authorized adversary simulation.",
  "installationId": "$(rand_guid)",
  "subscriptions": [
    {
      "id": "$sub_id",
      "name": "ADVSIM-DUMMY-Subscription",
      "state": "Enabled",
      "user": {
        "name": "$user_name",
        "type": "user"
      },
      "isDefault": true,
      "tenantId": "$tenant_id",
      "environmentName": "AzureCloud",
      "homeTenantId": "$tenant_id"
    }
  ]
}
EOF

  sp_env="$az_dir/advsim-sp-${RUN_ID}.env"
  write_new "$sp_env" <<EOF
# $MARKER run_id=$RUN_ID
# DUMMY Azure service principal for authorized adversary simulation.
AZURE_CLIENT_ID=$client_id
AZURE_TENANT_ID=$tenant_id
AZURE_CLIENT_SECRET=$client_secret
AZURE_SUBSCRIPTION_ID=$sub_id
ADVSIM_MARKER=$MARKER
ADVSIM_RUN_ID=$RUN_ID
EOF
}

# ---------------------------------------------------------------------------
# Other (kubeconfig, docker, git-credentials, npmrc, DO/Heroku, generic .env)
# ---------------------------------------------------------------------------
gen_other() {
  echo "==> other"

  # kubeconfig
  kube_dir="$TARGET/.kube"
  ensure_dir "$kube_dir"
  cluster="advsim-dummy-$(rand_hex 4)"
  write_new "$kube_dir/config" <<EOF
# $MARKER run_id=$RUN_ID
# DUMMY kubeconfig for authorized adversary simulation.
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    certificate-authority-data: $(printf 'ADVSIM-DUMMY-%s' "$RUN_ID" | openssl base64 -e 2>/dev/null | tr -d '\n' || printf 'QURWU0lNLURVTU1Z')
    server: https://advsim-dummy.example.local:6443
  name: $cluster
contexts:
- context:
    cluster: $cluster
    namespace: default
    user: advsim-decoy
  name: $cluster
current-context: $cluster
users:
- name: advsim-decoy
  user:
    token: advsim.${MARKER}.$(rand_alnum 48)
EOF

  # docker config.json
  docker_dir="$TARGET/.docker"
  ensure_dir "$docker_dir"
  # Fake auth: base64 of "advsim:ADVSIM-DUMMY-<runid>" without -w
  fake_auth=$(printf 'advsim:%s-%s' "$MARKER" "$RUN_ID" | openssl base64 -e 2>/dev/null | tr -d '\n' || printf 'YWR2c2ltOkFEVFNJTS1EVU1NWQ==')
  write_new "$docker_dir/config.json" <<EOF
{
  "_advsim": "$MARKER",
  "_advsim_run_id": "$RUN_ID",
  "_comment": "DUMMY docker config for authorized adversary simulation.",
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "$fake_auth"
    },
    "ghcr.io": {
      "auth": "$fake_auth"
    }
  }
}
EOF

  # ~/.git-credentials (avoid real ghp_ prefix — use advsim_ dummy scheme)
  write_new "$TARGET/.git-credentials" <<EOF
# $MARKER run_id=$RUN_ID
# DUMMY git credentials for authorized adversary simulation.
# Intentionally NOT a real GitHub/GitLab personal-access-token format.
https://advsim:${MARKER}-$(rand_alnum 32)@github.com
https://advsim:${MARKER}-$(rand_alnum 32)@gitlab.com
EOF

  # .npmrc
  write_new "$TARGET/.npmrc" <<EOF
; $MARKER run_id=$RUN_ID
; DUMMY npmrc for authorized adversary simulation.
//registry.npmjs.org/:_authToken=advsim-${MARKER}-$(rand_alnum 36)
always-auth=true
EOF

  # DigitalOcean-style token file
  do_dir="$TARGET/.config/doctl"
  ensure_dir "$do_dir"
  write_new "$do_dir/config.yaml" <<EOF
# $MARKER run_id=$RUN_ID
# DUMMY doctl config for authorized adversary simulation.
access-token: dop_v1_ADVSIM_DUMMY_$(rand_alnum 48)
auth-contexts:
  advsim:
    access-token: dop_v1_ADVSIM_DUMMY_$(rand_alnum 48)
context: advsim
EOF

  # Heroku-style
  heroku_dir="$TARGET/.config/heroku"
  ensure_dir "$heroku_dir"
  write_new "$heroku_dir/config.json" <<EOF
{
  "_advsim": "$MARKER",
  "_advsim_run_id": "$RUN_ID",
  "_comment": "DUMMY Heroku CLI config for authorized adversary simulation.",
  "ac": "advsim.${MARKER}.$(rand_alnum 40)",
  "addons": {},
  "skipInbox": true
}
EOF

  # Generic .env with DB URL
  write_new "$TARGET/.env" <<EOF
# $MARKER run_id=$RUN_ID
# DUMMY .env for authorized adversary simulation. Values are non-functional.
ADVSIM_MARKER=$MARKER
ADVSIM_RUN_ID=$RUN_ID
DATABASE_URL=postgres://advsim:${MARKER}_$(rand_alnum 16)@db.advsim.example.local:5432/advsim_dummy
REDIS_URL=redis://:${MARKER}_$(rand_alnum 12)@redis.advsim.example.local:6379/0
SECRET_KEY=$(rand_alnum 48)
API_TOKEN=advsim_${MARKER}_$(rand_alnum 32)
EOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
ran_any=0
if list_has "$ONLY" aws; then gen_aws; ran_any=1; fi
if list_has "$ONLY" gcp; then gen_gcp; ran_any=1; fi
if list_has "$ONLY" azure; then gen_azure; ran_any=1; fi
if list_has "$ONLY" other; then gen_other; ran_any=1; fi

if [ "$ran_any" -eq 0 ]; then
  echo "error: --only matched nothing useful (got: $ONLY)" >&2
  exit 2
fi

echo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry-run complete. No files written."
else
  echo "done. manifest: $MANIFEST"
  echo "cleanup later with: ./cleanup.sh --target \"$TARGET\""
fi
