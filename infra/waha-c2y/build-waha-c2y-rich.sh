#!/usr/bin/env bash
set -euo pipefail

# Builds an INTERNAL WAHA image with the Autonom.ia patch c2y-rich-1 (autonom-ia2/chat#1709):
# native list / location / contact from Chatwoot + list replies back to Chatwoot.
#
# Overlays ONLY the changed dist JS (and .map) of WAHA 2026.9.2 (commit 90ba445a) + patch onto an
# EXPLICIT base image (digest or image ID). The base is never pulled implicitly. It never pushes,
# never deploys, never touches volumes or sessions. Files are read from images with
# docker create + docker cp, so no amd64 code runs on the build host.
#
# Usage:
#   WAHA_C2Y_BASE=<repo@sha256:...|sha256:<image id>> ./build-waha-c2y-rich.sh [image-tag]
# Optional:
#   WAHA_C2Y_DIST_DIR    pre-built patched dist (skips the node builder); verified against the reviewed hashes
#   WAHA_C2Y_PATCH       patch file for the builder (default: waha-2026.9.2-c2y-rich.patch next to this script)
#   WAHA_C2Y_NODE_IMAGE  builder node image, must already be local (default node:24.11.0-bookworm-slim)
#   WAHA_C2Y_BASE_SOURCE upstream reference of the base (e.g. repo@sha256:<digest>) when it was moved
#                        with docker save/load and only the local image ID is left; recorded as a label
#   WAHA_C2Y_OUT_DIR     write `docker save` of the final image + its sha256 there
#   WAHA_C2Y_SKIP_SMOKE=1  required when the docker daemon can not run linux/amd64 (smoke left to the canary)

IMAGE_TAG="${1:-autonomia-waha-c2y-rich:verify}"
BASE_IMAGE="${WAHA_C2Y_BASE:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${WAHA_C2Y_DIST_DIR:-}"
PATCH_FILE="${WAHA_C2Y_PATCH:-$SCRIPT_DIR/waha-2026.9.2-c2y-rich.patch}"
NODE_IMAGE="${WAHA_C2Y_NODE_IMAGE:-node:24.11.0-bookworm-slim}"
BASE_SOURCE="${WAHA_C2Y_BASE_SOURCE:-$BASE_IMAGE}"
OUT_DIR="${WAHA_C2Y_OUT_DIR:-}"
SKIP_SMOKE="${WAHA_C2Y_SKIP_SMOKE:-0}"
NODE_VERSION="v24.11.0"
WAHA_REPO="https://github.com/devlikeapro/waha.git"
WAHA_TAG="2026.9.2"
WAHA_SHA="90ba445a0e765701c8910f0fac08176250c3e0fd"
PATCH_ID="c2y-rich-1"
ISSUE="chat#1709"
PLATFORM="linux/amd64"
SMOKE_KEY="c2y-rich-smoke-key-$$"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/waha-c2y-rich.XXXXXX")"
BUILDER_TAG="autonomia-waha-c2y-rich-builder:$$"
SMOKE="autonomia-waha-c2y-rich-smoke-$$"
BUILT_BUILDER=0
CONTAINERS=()

cleanup() {
  docker rm -f "$SMOKE" >/dev/null 2>&1 || true
  for c in "${CONTAINERS[@]+"${CONTAINERS[@]}"}"; do docker rm -f "$c" >/dev/null 2>&1 || true; done
  if [[ "$BUILT_BUILDER" == "1" ]]; then docker image rm -f "$BUILDER_TAG" >/dev/null 2>&1 || true; fi
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() { echo "ERROR: $*" >&2; exit "${2:-1}"; }
sha() { sha256sum "$1" | awk '{print $1}'; }

for cmd in docker sha256sum awk; do command -v "$cmd" >/dev/null || fail "missing dependency: $cmd" 2; done
docker buildx version >/dev/null 2>&1 || fail "missing dependency: docker buildx" 2

#
# Reviewed hashes. BEFORE = WAHA 2026.9.2 unpatched dist, AFTER = with the patch.
# Built with node v24.11.0 + yarn 4.17.1 + typescript 5.9.2 (yarn.lock of the tag).
# "NEW" = file must not exist in the base.
#
RUNTIME_FILES=$(cat <<'EOF'
0c1ca1d721db466c34330ccd631f6f8c2c8f36d8fd4388cfa0dd113a3afaba7f 0322ffe6f06d0eb1fc181004e1190f22506f80b83589e3711ee5210cf48bd334 apps/app_sdk/waha/WAHASelf.js
7417b6f049b87482de35e14ac4c43aff187ffb28a291edb5aff865120b4ac04a a37eb8f18b06cc3ccf0c11976895b3c2fa1596b18ffe5cb1377f0387cec1d1dc apps/chatwoot/consumers/inbox/message_created.js
63475a6e0ac4f714d815e6fd07c27bc8849c6eabda1001faa007098709c39f10 03f200963115d786ef44327c1a509d06c4acd1ca2819f476eaf095e6b7d501a0 apps/chatwoot/consumers/waha/base.js
f134da1e0d5a6153d997632876af48d038a4a2b0ee514129fdba101efe17d0ba 67856d5e3cbc58d1c0594ec2b7c8faed265ef9716dfb0f59ef939fbf28207dd1 apps/chatwoot/error/ChatWootErrorReporter.js
894a2d40227e711aa76d8e9c5d758febd4f9f7dab016aaeb2aefd5b3fc0edc62 e990cc5a81323d6c41462bbdefc3aa00233b21539c53499bf79ab7037af0e0a0 structures/environment.dto.js
853308109c1a7dbbe4798c943bd578016d93bcb2f5a7727e3b18374bf749b97d 83be1f3d8b2f8194da698afd8d782969ec93575e1bb2777f2b999e8099ed5c52 utils/bull/BaseWorkerHost.js
91859392794b5bfdfd633e7dce77a3749b0e8d8216d949493f15801ec2730e38 f7cdaf65df40dc578be0556d6f7b329c5eb412a58de04c5e939a8d2b4e2849c0 version.js
NEW f424d5b86758904a5d31097133f3864323cf16a2f2b4b61b87935f5e064f726a apps/chatwoot/messages/to/chatwoot/ListReply.js
NEW 697db03575396bc8be9f41c5cb02e6ef56d31b6ad2198a39ac6a19219848cd60 apps/chatwoot/messages/to/whatsapp/native.js
EOF
)

# Copy one file out of a created (never started) container. Non-zero when the file is absent.
# usage: copy_from_container <container-id> <path-in-image> <local-dest>
copy_from_container() {
  mkdir -p "$(dirname "$3")"
  docker cp "$1:$2" "$3" >/dev/null 2>&1
}

new_container() {
  docker create --platform "$PLATFORM" --network none "$1" /bin/true
}

#
# 0. Inputs - fail closed
#
[[ -n "$BASE_IMAGE" ]] || fail "WAHA_C2Y_BASE is required (repo@sha256:<digest> or sha256:<image id>)" 2
if [[ "$BASE_IMAGE" != *@sha256:* && "$BASE_IMAGE" != sha256:* ]]; then
  fail "WAHA_C2Y_BASE must be pinned by digest or image ID, not a tag: $BASE_IMAGE" 2
fi
docker image inspect "$BASE_IMAGE" >/dev/null 2>&1 ||
  fail "refusing to pull implicitly: base image is not present locally: $BASE_IMAGE" 3
base_platform="$(docker image inspect "$BASE_IMAGE" --format '{{.Os}}/{{.Architecture}}')"
[[ "$base_platform" == "$PLATFORM" ]] || fail "base image platform is $base_platform, expected $PLATFORM" 3
base_id="$(docker image inspect "$BASE_IMAGE" --format '{{.Id}}')"
# BuildKit can not use a bare image ID in FROM: pin a stable local tag to the same ID (kept, never pushed)
BASE_LOCAL="autonomia-waha-c2y-base:${base_id#sha256:}"
BASE_LOCAL="${BASE_LOCAL:0:43}"
docker tag "$BASE_IMAGE" "$BASE_LOCAL"
[[ "$(docker image inspect "$BASE_LOCAL" --format "{{.Id}}")" == "$base_id" ]] || fail "local base tag does not point to $base_id" 3
patch_sha="none"
[[ -f "$PATCH_FILE" ]] && patch_sha="$(sha "$PATCH_FILE")"

#
# 1. Base compatibility: the original JS in the base must be exactly the reviewed 2026.9.2 build
#
echo "[1/5] Checking base $BASE_IMAGE ($base_id), no code executed"
base_cid="$(new_container "$BASE_IMAGE")"
CONTAINERS+=("$base_cid")
while read -r before _after file; do
  [[ -n "$file" ]] || continue
  local_copy="$TMP/base/$file"
  if [[ "$before" == "NEW" ]]; then
    if copy_from_container "$base_cid" "/app/dist/$file" "$local_copy"; then
      fail "refusing overlay: /app/dist/$file already exists in the base (unknown layout)" 4
    fi
    continue
  fi
  copy_from_container "$base_cid" "/app/dist/$file" "$local_copy" || fail "base lacks /app/dist/$file" 4
  actual="$(sha "$local_copy")"
  [[ "$actual" == "$before" ]] || fail "refusing overlay: base differs at /app/dist/$file (got $actual)" 4
done <<< "$RUNTIME_FILES"
echo "      base matches WAHA $WAHA_TAG ($WAHA_SHA)"

#
# 2. Patched dist: pre-built dir, or the node builder (pinned node, exact commit, patch, frozen lockfile)
#
STAGE="$TMP/context/dist"
if [[ -n "$DIST_DIR" ]]; then
  echo "[2/5] Using pre-built dist $DIST_DIR"
  [[ -d "$DIST_DIR" ]] || fail "WAHA_C2Y_DIST_DIR is not a directory: $DIST_DIR" 2
  while read -r _before _after file; do
    [[ -n "$file" ]] || continue
    for f in "$file" "$file.map"; do
      [[ -f "$DIST_DIR/$f" ]] || fail "missing in dist: $f" 5
      mkdir -p "$(dirname "$STAGE/$f")"
      cp "$DIST_DIR/$f" "$STAGE/$f"
    done
  done <<< "$RUNTIME_FILES"
else
  echo "[2/5] Building patched dist (builder, not shipped)"
  [[ -f "$PATCH_FILE" ]] || fail "patch not found: $PATCH_FILE" 2
  docker image inspect "$NODE_IMAGE" >/dev/null 2>&1 ||
    fail "refusing to pull implicitly: builder node image is not present locally: $NODE_IMAGE" 3
  cp "$PATCH_FILE" "$TMP/c2y-rich.patch"
  cat > "$TMP/Dockerfile.builder" <<EOF
FROM $NODE_IMAGE
ENV PUPPETEER_SKIP_DOWNLOAD=True
RUN apt-get update && \\
    apt-get install -y --no-install-recommends git python3 build-essential ca-certificates && \\
    rm -rf /var/lib/apt/lists/*
RUN test "\$(node --version)" = "$NODE_VERSION"
WORKDIR /git
RUN git init -q && git remote add origin $WAHA_REPO && \\
    git fetch -q --depth 1 origin refs/tags/$WAHA_TAG && \\
    test "\$(git rev-parse 'FETCH_HEAD^{commit}')" = "$WAHA_SHA" && \\
    git checkout -q FETCH_HEAD
COPY c2y-rich.patch /tmp/c2y-rich.patch
RUN git apply --check /tmp/c2y-rich.patch && git apply /tmp/c2y-rich.patch
# yarn 4 (packageManager of the tag): --immutable is the --frozen-lockfile equivalent
RUN npm install -g corepack && corepack enable && yarn install --immutable
RUN yarn build && find ./dist -name "*.d.ts" -delete
EOF
  docker build --pull=false -q -f "$TMP/Dockerfile.builder" -t "$BUILDER_TAG" "$TMP" >/dev/null
  BUILT_BUILDER=1
  builder_cid="$(docker create --network none "$BUILDER_TAG" /bin/true)"
  CONTAINERS+=("$builder_cid")
  while read -r _before _after file; do
    [[ -n "$file" ]] || continue
    for f in "$file" "$file.map"; do
      copy_from_container "$builder_cid" "/git/dist/$f" "$STAGE/$f" || fail "builder did not produce dist/$f" 5
    done
  done <<< "$RUNTIME_FILES"
fi

# The patched dist must be byte-identical to the reviewed one
while read -r _before after file; do
  [[ -n "$file" ]] || continue
  actual="$(sha "$STAGE/$file")"
  [[ "$actual" == "$after" ]] || fail "patched dist differs from the reviewed hash at $file (got $actual)" 5
done <<< "$RUNTIME_FILES"
echo "      patched dist matches the reviewed hashes"

#
# 3. Overlay: only the changed JS + .map, nothing else (FROM, COPY, LABEL - no RUN)
#
echo "[3/5] Building overlay $IMAGE_TAG ($PLATFORM, no pull)"
{
  echo "FROM $BASE_LOCAL"
  while read -r _before _after file; do
    [[ -n "$file" ]] || continue
    echo "COPY dist/$file /app/dist/$file"
    echo "COPY dist/$file.map /app/dist/$file.map"
  done <<< "$RUNTIME_FILES"
  echo "LABEL autonomia.base-digest=\"$BASE_SOURCE\" \\"
  echo "      autonomia.base-ref=\"$BASE_IMAGE\" \\"
  echo "      autonomia.base-image-id=\"$base_id\" \\"
  echo "      autonomia.waha-sha=\"$WAHA_SHA\" \\"
  echo "      autonomia.waha-tag=\"$WAHA_TAG\" \\"
  echo "      autonomia.patch=\"$PATCH_ID\" \\"
  echo "      autonomia.patch-sha256=\"$patch_sha\" \\"
  echo "      autonomia.issue=\"$ISSUE\""
} > "$TMP/context/Dockerfile"
docker buildx build --load --pull=false --platform "$PLATFORM" -q \
  -t "$IMAGE_TAG" "$TMP/context" >/dev/null

#
# 4. Verify inside the final image, without running it
#
echo "[4/5] Verifying the final image (docker create + docker cp)"
[[ "$(docker image inspect "$IMAGE_TAG" --format '{{.Os}}/{{.Architecture}}')" == "$PLATFORM" ]] ||
  fail "final image is not $PLATFORM" 5
final_cid="$(new_container "$IMAGE_TAG")"
CONTAINERS+=("$final_cid")
while read -r _before after file; do
  [[ -n "$file" ]] || continue
  local_copy="$TMP/final/$file"
  copy_from_container "$final_cid" "/app/dist/$file" "$local_copy" || fail "final image lacks /app/dist/$file" 5
  actual="$(sha "$local_copy")"
  [[ "$actual" == "$after" ]] || fail "final image differs at /app/dist/$file (got $actual)" 5
  echo "      $actual /app/dist/$file"
done <<< "$RUNTIME_FILES"

#
# 5. Isolated smoke: no network, no mounts, no WhatsApp session (needs a daemon that runs amd64)
#
daemon_arch="$(docker info --format '{{.Architecture}}')"
if [[ "$daemon_arch" != "x86_64" ]]; then
  [[ "$SKIP_SMOKE" == "1" ]] ||
    fail "docker daemon is $daemon_arch and can not run $PLATFORM; set WAHA_C2Y_SKIP_SMOKE=1 to leave the smoke to the canary" 6
  echo "[5/5] SMOKE NOT RUN: daemon is $daemon_arch (no amd64 emulation). Run it on an amd64 host (canary)."
else
  echo "[5/5] Isolated smoke (--network none, no mounts)"
  docker run -d --name "$SMOKE" --platform "$PLATFORM" --network none \
    -e WAHA_API_KEY="$SMOKE_KEY" "$IMAGE_TAG" >/dev/null
  [[ "$(docker inspect "$SMOKE" --format '{{.HostConfig.NetworkMode}}')" == "none" ]] || fail "smoke container has network" 6
  [[ "$(docker inspect "$SMOKE" --format '{{len .Mounts}}')" == "0" ]] || fail "smoke container has mounts" 6
  ok=0
  for _ in $(seq 1 60); do
    if docker exec "$SMOKE" sh -c "curl -fsS -H 'X-Api-Key: $SMOKE_KEY' http://127.0.0.1:3000/api/server/version > /tmp/version.json"; then
      ok=1
      break
    fi
    sleep 1
  done
  logs="$(docker logs "$SMOKE" 2>&1 || true)"
  [[ "$ok" == "1" ]] || { printf '%s\n' "$logs" | tail -50 >&2; fail "WAHA did not answer /api/server/version" 6; }
  version="$(docker exec "$SMOKE" cat /tmp/version.json)"
  [[ "$version" == *"\"version\":\"$WAHA_TAG\""* ]] || fail "unexpected WAHA version: $version" 7
  expected_ext='"autonomia":{"patch":"c2y-rich-1","rich_native":["options","location","contact"],"list_reply":true}'
  [[ "$version" == *"$expected_ext"* ]] || fail "autonomia handshake missing in /api/server/version: $version" 7
  # Leak check: the api key and the header name must never reach the log
  if printf '%s\n' "$logs" | grep -qiE "x-api-key|$SMOKE_KEY"; then
    fail "smoke log contains the api key or its header" 8
  fi
  docker rm -f "$SMOKE" >/dev/null
fi

image_id="$(docker image inspect "$IMAGE_TAG" --format '{{.Id}}')"
if [[ -n "$OUT_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  tarball="$OUT_DIR/$(echo "$IMAGE_TAG" | tr '/:' '__').tar"
  docker save -o "$tarball" "$IMAGE_TAG"
  (cd "$OUT_DIR" && sha256sum "$(basename "$tarball")" > "$(basename "$tarball").sha256")
  echo "      saved $tarball ($(wc -c < "$tarball" | tr -d ' ') bytes) sha256=$(sha "$tarball")"
fi
echo "OK image=$IMAGE_TAG id=$image_id base=$BASE_IMAGE waha=$WAHA_TAG/$WAHA_SHA patch=$PATCH_ID ($patch_sha)"
echo "Nothing was pushed or deployed. Deploy needs explicit approval and its own rollback plan."
