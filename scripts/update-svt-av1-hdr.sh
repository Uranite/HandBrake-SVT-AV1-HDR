#!/usr/bin/env bash
#
# Pin HandBrake's SVT-AV1 contrib to the latest SVT-AV1-HDR main commit.
#
# - Resolves the newest commit on the upstream branch (main by default).
# - Builds a reproducible, versioned tarball (rooted at svt-av1-hdr-<sha>).
# - Uploads it to the "contribs" release of this repository.
# - Regenerates patches/0004-change-repo-url.patch against current HandBrake
#   and validates that the whole patch set still applies.
#
# Environment:
#   UPSTREAM_REPO    upstream repository            (default juliobbv-p/SVT-AV1-HDR)
#   UPSTREAM_REF     branch/tag/commit to follow    (default main)
#   RELEASE_REPO     repository owning the asset    (default $GITHUB_REPOSITORY)
#   RELEASE_TAG      release that stores assets     (default contribs)
#   HANDBRAKE_REF    HandBrake branch for validation(default master)
#   VALIDATE         all, 0004, or none             (default all)
#   DRY_RUN          1 to skip uploads and writes

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REPO="${UPSTREAM_REPO:-juliobbv-p/SVT-AV1-HDR}"
UPSTREAM_REF="${UPSTREAM_REF:-main}"
RELEASE_REPO="${RELEASE_REPO:-${GITHUB_REPOSITORY:-Uranite/HandBrake-SVT-AV1-HDR}}"
RELEASE_TAG="${RELEASE_TAG:-contribs}"
HANDBRAKE_REF="${HANDBRAKE_REF:-master}"
VALIDATE="${VALIDATE:-all}"
DRY_RUN="${DRY_RUN:-0}"

PATCH_FILE="$ROOT_DIR/patches/0004-change-repo-url.patch"

log() {
    printf '%s\n' "$*" >&2
}

die() {
    log "error: $*"
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        python3 - "$1" <<'PY'
import hashlib
import sys

with open(sys.argv[1], "rb") as handle:
    print(hashlib.sha256(handle.read()).hexdigest())
PY
    fi
}

# Print "1|<sha256>" when the asset exists (digest may be empty), else "0|".
release_asset_state() {
    local name="$1"
    local json
    json="$(gh api "repos/${RELEASE_REPO}/releases/tags/${RELEASE_TAG}" 2>/dev/null || true)"
    if [[ -z "$json" ]]; then
        printf '0|'
        return 0
    fi
    printf '%s' "$json" | python3 - "$name" <<'PY'
import json
import sys

name = sys.argv[1]
try:
    release = json.load(sys.stdin)
except Exception:
    print("0|")
    raise SystemExit(0)

for asset in release.get("assets", []):
    if asset.get("name") == name:
        digest = (asset.get("digest") or "").removeprefix("sha256:")
        print(f"1|{digest}")
        break
else:
    print("0|")
PY
}

need gh
need curl
need git
need python3
need patch

read -r COMMIT COMMIT_DATE < <(
    gh api "repos/${UPSTREAM_REPO}/commits/${UPSTREAM_REF}" \
        --jq '[.sha, .commit.committer.date] | @tsv'
)
[[ -n "$COMMIT" ]] || die "could not resolve ${UPSTREAM_REPO}@${UPSTREAM_REF}"

SHORT_COMMIT="${COMMIT:0:12}"
ASSET_NAME="svt-av1-hdr-${SHORT_COMMIT}.tar.gz"
TARBALL_ROOT="svt-av1-hdr-${SHORT_COMMIT}"
URL="https://github.com/${RELEASE_REPO}/releases/download/${RELEASE_TAG}/${ASSET_NAME}"

log "Upstream : ${UPSTREAM_REPO}@${UPSTREAM_REF}"
log "Commit   : ${COMMIT} (${COMMIT_DATE})"
log "Asset    : ${ASSET_NAME}"

CURRENT_URL=""
CURRENT_SHA=""
if [[ -f "$PATCH_FILE" ]]; then
    CURRENT_URL="$(sed -n 's/^+SVT-AV1\.FETCH\.url[[:space:]]*=[[:space:]]*//p' "$PATCH_FILE" | head -n 1)"
    CURRENT_SHA="$(sed -n 's/^+SVT-AV1\.FETCH\.sha256[[:space:]]*=[[:space:]]*//p' "$PATCH_FILE" | head -n 1)"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

IFS='|' read -r ASSET_EXISTS REMOTE_DIGEST <<<"$(release_asset_state "$ASSET_NAME")"

LOCAL_ASSET=""
NEED_UPLOAD=0

if [[ "$ASSET_EXISTS" == "1" && -n "$REMOTE_DIGEST" ]]; then
    SHA256="$REMOTE_DIGEST"
    log "Reusing ${ASSET_NAME} (sha256 ${SHA256})"
else
    log "Downloading ${UPSTREAM_REPO} source at ${SHORT_COMMIT}..."
    SRC_ARCHIVE="$TMP_DIR/source.tar.gz"
    curl -fsSL --retry 3 --retry-delay 2 \
        -o "$SRC_ARCHIVE" \
        "https://github.com/${UPSTREAM_REPO}/archive/${COMMIT}.tar.gz"

    LOCAL_ASSET="$TMP_DIR/$ASSET_NAME"
    python3 "$ROOT_DIR/scripts/package-svt-av1-hdr.py" \
        --input "$SRC_ARCHIVE" \
        --output "$LOCAL_ASSET" \
        --root "$TARBALL_ROOT"
    SHA256="$(hash_file "$LOCAL_ASSET")"
    NEED_UPLOAD=1
    log "Built ${ASSET_NAME} (sha256 ${SHA256})"
fi

if [[ -n "$CURRENT_SHA" && "$CURRENT_SHA" != "$SHA256" ]]; then
    log "Pinned sha256 changes: ${CURRENT_SHA} -> ${SHA256}"
elif [[ "$CURRENT_SHA" == "$SHA256" ]]; then
    log "Pinned sha256 already matches"
fi

# Regenerate 0004 against the current HandBrake tree so that HandBrake's own
# SVT-AV1 version bumps cannot make the patch context stale.
BASELINE="$TMP_DIR/module.defs"
curl -fsSL --retry 3 --retry-delay 2 \
    -o "$BASELINE" \
    "https://raw.githubusercontent.com/HandBrake/HandBrake/${HANDBRAKE_REF}/contrib/svt-av1/module.defs"

CANDIDATE="$TMP_DIR/0004-change-repo-url.patch"
python3 "$ROOT_DIR/scripts/render-patch-0004.py" \
    --input "$BASELINE" \
    --url "$URL" \
    --sha256 "$SHA256" \
    --output "$CANDIDATE"

CHANGED=true
if [[ ! -s "$CANDIDATE" ]]; then
    CHANGED=false
    log "HandBrake module.defs already contains this pin"
elif [[ -f "$PATCH_FILE" ]] && cmp -s "$CANDIDATE" "$PATCH_FILE"; then
    CHANGED=false
    log "Patch 0004 is already up to date"
fi

if [[ "$CHANGED" == "true" && "$VALIDATE" != "none" ]]; then
    log "Validating patches against HandBrake ${HANDBRAKE_REF}..."
    HANDBRAKE_DIR="$TMP_DIR/HandBrake"
    git clone --depth 1 --branch "$HANDBRAKE_REF" \
        https://github.com/HandBrake/HandBrake.git "$HANDBRAKE_DIR" >/dev/null 2>&1 \
        || die "could not clone HandBrake ${HANDBRAKE_REF}"

    for patch_file in "$ROOT_DIR"/patches/*.patch; do
        if [[ "$(basename "$patch_file")" == "0004-change-repo-url.patch" ]]; then
            patch_file="$CANDIDATE"
        fi
        if [[ "$VALIDATE" == "0004" && "$(basename "$patch_file")" != "0004-change-repo-url.patch" ]]; then
            continue
        fi
        log "  applying $(basename "$patch_file")"
        patch -t -N -p1 -d "$HANDBRAKE_DIR" <"$patch_file" >/dev/null \
            || die "patch failed: $(basename "$patch_file")"
    done

    grep -qF "$URL" "$HANDBRAKE_DIR/contrib/svt-av1/module.defs" \
        || die "patched module.defs does not contain the new URL"
    grep -qF "$SHA256" "$HANDBRAKE_DIR/contrib/svt-av1/module.defs" \
        || die "patched module.defs does not contain the new sha256"
    log "All patches apply cleanly"
fi

if [[ "$NEED_UPLOAD" == "1" && "$DRY_RUN" != "1" ]]; then
    if ! gh release view "$RELEASE_TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
        gh release create "$RELEASE_TAG" \
            --repo "$RELEASE_REPO" \
            --target main \
            --title "Contrib sources" \
            --notes "Automated SVT-AV1-HDR source archives."
    fi
    log "Uploading ${ASSET_NAME} to ${RELEASE_REPO}#${RELEASE_TAG}..."
    gh release upload "$RELEASE_TAG" "$LOCAL_ASSET" \
        --repo "$RELEASE_REPO" --clobber

    UPLOADED_DIGEST="$(release_asset_state "$ASSET_NAME" | cut -d'|' -f2)"
    if [[ -n "$UPLOADED_DIGEST" && "$UPLOADED_DIGEST" != "$SHA256" ]]; then
        die "uploaded asset digest mismatch: ${UPLOADED_DIGEST} != ${SHA256}"
    fi
fi

if [[ "$CHANGED" == "true" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY_RUN: not writing patch 0004"
        sed 's/^/    /' "$CANDIDATE" >&2
    else
        cp "$CANDIDATE" "$PATCH_FILE"
        log "Updated ${PATCH_FILE#"$ROOT_DIR"/}"
    fi
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "changed=${CHANGED}"
        echo "version=${SHORT_COMMIT}"
        echo "commit=${COMMIT}"
        echo "sha256=${SHA256}"
        echo "url=${URL}"
    } >>"$GITHUB_OUTPUT"
fi

log "Done: ${UPSTREAM_REPO}@${SHORT_COMMIT} (changed=${CHANGED})"
