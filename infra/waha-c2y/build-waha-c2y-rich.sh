#!/usr/bin/env bash
set -euo pipefail

# Builds an INTERNAL WAHA image with the Autonom.ia patch c2y-rich-3 (autonom-ia2/chat#1709):
# c2y-rich-1 (native list / location / contact, list replies) plus native poll and poll votes,
# media as media, calls / unknown messages / reactions / edits as structured data to Chatwoot,
# reactions and edits from Chatwoot (accepted only with the inbox HMAC signature), preformatted
# text (waha_text). Revision 2b: review fixes (poll.vote.failed, error note type, c2y_* signature
# with the raw body kept by main.js, 16 MB / 50 MP cap on image conversion).
# c2y-rich-3 (round 2): incoming media / album / location / contacts / quote / failed download /
# revoke / context (ephemeral, forwarded) / order as structured data next to the unchanged
# message, played receipt (c2y_played_at), event responses, link card with custom preview and
# event out (sendLinkCustomPreview, sendEvent). Media download retry is OFF unless
# WAHA_C2Y_MEDIA_RETRY=true.
# Revision 3b: review fixes (event responses only for events the connector sent, failed download
# only on media.error, from_me in waha_media_failed / waha_order, ephemeral expiration null when the
# message does not say). Same PATCH_ID (version.ts unchanged); the patch sha256 label tells them apart.
#
# Overlays ONLY the changed dist files (JS + .map, and 2 locale YAML) of WAHA 2026.9.2 (commit 90ba445a) + patch onto an
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
PATCH_ID="c2y-rich-4"
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
# "NEW" = file must not exist in the base. Only .js entries have a .map next to them.
#
RUNTIME_FILES=$(cat <<'EOF'
0c1ca1d721db466c34330ccd631f6f8c2c8f36d8fd4388cfa0dd113a3afaba7f d6db0b3a3769cac14af699e0f3267e0be9f187c7c426017ffb3e2d8c9b36a3c3 apps/app_sdk/waha/WAHASelf.js
f2b920a68164eb5d2f032acd4a0ca021a93e0da703576760e59ca6643183173c 22564b80589c93b93335985248c95e86196be9dd8c315799de7815e8be28ddd6 apps/chatwoot/api/chatwoot.webhook.controller.js
b95bb1438a2f83d5e33cd018df36af7bb939747886e80ac6ddd98090946a2333 23b46b616cc0fdf70eac6aae78de63100fd9df0a517ddf920cf2987fa0241074 apps/chatwoot/app.module.js
857bc73880a485eec6d78b7b8c1f831e20e855bca884a999a6172aeb9d34484d cd628a7297f254b09c4295f13b0408694573845a0c9f557b138e1b7e7ff3ae9b apps/chatwoot/client/Conversation.js
760fc9256f4ca924ddc696538fe92418fe92837795d89b7ce7f89e81c4b54c80 256ee917d010879b8bacc91f37f613e80ab6b546856ecdbf06099e6b5bbc3e11 apps/chatwoot/consumers/QueueName.js
7417b6f049b87482de35e14ac4c43aff187ffb28a291edb5aff865120b4ac04a 2df4403238e913cce70ae5a9baac272f021a84b06a8f4ed10dc790f347709d05 apps/chatwoot/consumers/inbox/message_created.js
df508d28a37dd944295d16cb07068e634d7b6c990636dacf55adc92857d439f5 6cf293caae44cdb71312d70aaf60b349f4ace440fd9a6e69abc7a97b14185ebd apps/chatwoot/consumers/inbox/message_deleted.js
63475a6e0ac4f714d815e6fd07c27bc8849c6eabda1001faa007098709c39f10 275fe36f76c85a727a82af7e3527afe6863c7653bb48bc08a1bcd37e98275de1 apps/chatwoot/consumers/waha/base.js
df4a6514754eeb5e851c9790c8a2aabe64470e963d55b7ca502d6cf020444ca0 bb02f2e999ffd7235151ac650b86ce603aed6e227c4cc416ec87c40e6ac2845e apps/chatwoot/consumers/waha/call.0.base.js
e65fc6b87b7ab3c6ae5567f67274bc0ffb14d1b2256e6c0a68aff42de40614dc 577bdf04b578f86e8fc283cb8a877e191e6546f405b7904194dbf612f80541f7 apps/chatwoot/consumers/waha/call.accepted.js
53202f31130b28d8be9a93467266216c9ca03e67158f52e9d0e114d4d02a3b34 d8402b23a20b2fb6b2beb0d144ac31b864589ed31123062ebc609e1972e3cf51 apps/chatwoot/consumers/waha/call.received.js
73eab2dc7814bb6d31532f1921fd53e38122478666092d590d6c60a7620e1cbf f86576452e1ed56e84a765c93a57a07ac75500ea7ec8d42297b46cabb9adefb5 apps/chatwoot/consumers/waha/call.rejected.js
894da6ec09c9072592f593f0003f89bd04f12e494b2f5694d0f16081088795fd 80d457e76c6f546e2ff2d67d8a22861fa990ccd07dac4a9913d6460c5f85972f apps/chatwoot/consumers/waha/message.ack.js
92a084f4c0de30f514e19d964e145a9ad8d786e24dcbf3015205b03bcc5c4a19 7c67af5a56be64a4b3f00dd578df637fbe4216112c3c6009b4eba1186abb25d7 apps/chatwoot/consumers/waha/message.any.js
35cdb434a95bd70648b34116f950a70b1c752df53733a6632d2d2ed46b910361 71c0ea06809620c7d6354a30af0af9afdc23ea7698485e2db2420f264919b18b apps/chatwoot/consumers/waha/message.reaction.js
608cf31ecff209302ae1b1c49b428ae42a364101ac4bb1008565593d5e3db8e5 6b19de72396fb11d9b66fe67bda7c682a85d36d80ac80674fecda9d97c8c4dda apps/chatwoot/consumers/waha/message.revoked.js
f134da1e0d5a6153d997632876af48d038a4a2b0ee514129fdba101efe17d0ba 67856d5e3cbc58d1c0594ec2b7c8faed265ef9716dfb0f59ef939fbf28207dd1 apps/chatwoot/error/ChatWootErrorReporter.js
e43003d4bcc2505181dd92970a24680caeaf73a936dba0df09909df075a57b1f 9a96b22cb65ab4b7af710043e3090b99bddedea6061a61193ed38620ae55bb78 apps/chatwoot/i18n/locales/en-US.yaml
d0d325faf27759653d3b37bafd0cfd3d97884cde92a098941694a8e8648ed129 b551a5034b1639b72ee8280e6a3f3f2446d5962b938299a8bf13e030dbcf93a9 apps/chatwoot/i18n/locales/pt-BR.yaml
9ac783284503d336cee683ea83d22439f2e0e49aef5b8a6c5282f6624c478383 857d2e1b4507ac3c231cefd9995efb9c450ee4fbfa03797bdeefcf2830cb6bcc apps/chatwoot/messages/to/chatwoot/AlbumMessage.js
7faabd7d7dfe5b7c157e40ecc5f7dfba2bc8a6ee6f46ffa265086854ce1019c4 62d2e9b13681db5006070570e84da2a0024b215cbdfcd6164e4877e638b9b439 apps/chatwoot/messages/to/chatwoot/HasMediaWithNoMediaMessage.js
a62b52ebf98d44d251877753a182e99206591360d562cd71cf406abb4d9e3e48 33f21efda666401dfebf6a1f07867d0c8624727da6a46f92da1cdc65b90ace7c apps/chatwoot/messages/to/chatwoot/LocationMessage.js
b9c1f82e7f9a96b9790526d2301a2129eb5d49701a6c5945e778f686fd86b6ee 221488002b6c04ab8eb35512876e5a8e4fe59c87b8df87467abb18aab9fdd3f2 apps/chatwoot/messages/to/chatwoot/MessageEdited.js
db1114a5f7c888b6a5ee641b8c1a1ed0d226410e20ad52c7382c66b8827b8a68 aaa4620e1b30a8e1cde5e638da1ec322673bf3300b3f05f65045b7666de88010 apps/chatwoot/messages/to/chatwoot/ShareContactMessage.js
02a90d7885675088b97cb046039f0f1f91ae8e7f79bdf6c9345c2b180184ae58 9f535aa531a8bc4b064910dbd4eaa0a4493f9d6c2677c9fb2c528b5a5ebe1f78 apps/chatwoot/messages/to/chatwoot/TextMessage.js
3e6e76e57ed306dfb19b8056b4903877f786e77aa1c4c6c4df7897db73cab3c1 844f8e37190e4f9510bbdc5fa60684a2b9afe657ded7695d21787002b935a4c5 apps/chatwoot/messages/to/chatwoot/UnsupportedMessage.js
41b8cd5b444122e1b29fd2c3a73aee677f03ded6f67009006bdc9675659c8594 3246efc79f487cc0a76086fbfe8d6b7bc1f3fb88c19e70c5d15b1551d539b23c apps/chatwoot/services/ChatWootQueueService.js
a0d42f54af317c7b9aea696aca9fa36b712849f64e63fbb29ee7f1697c95c020 6b4fdaa4de5cca553754a8c25ba28abc8e9dbf9c538f90570ba10ce37e7bd753 apps/chatwoot/services/ChatWootWAHAQueueService.js
530102b3079f35cf7e1392ae1c431b01c67806344e7485751110c6c41f8b12ca 43e1b3d1dcd4e0484c084bbbb657586e7ecd152c937c9b91bd1a95689c7c66b5 apps/chatwoot/services/MessageStatusService.js
7dfa8e5ffc32f5e6a0ab27db49e212c3aadeaf94b72129cec8f5a78e8af304c9 ecffa08a4a75320c66c1d9a6a3d202b52ce82bb30649cc23018e30eab4d6a141 apps/chatwoot/services/QueueManager.js
bd742b80ff13766a79196bbf6c79e5831d44f0296e9a0eb3317e8442bd728cd2 2392ec7d292e6dcb33a70b1b99746e5b616657401854e5e0d6f9f202a2d8dfd5 apps/chatwoot/services/QueueRegistry.js
3306556bf6dc16c386d3667c93133abf4dfce93e36c866aefc4b6042fe3b4691 41f86dd260a12e4c505db4b24704dac0781d1f7a7773a6eb29924fe51c33b592 core/engines/gows/session.gows.core.js
c558d676f8652e20202b3bf0ab48a59b70312ee56081f53f7cf99ff5e819dc01 277f27742b222dcda412edc23e09b9278f2cb295bbdcbd6869c96e94c02d29d4 main.js
894a2d40227e711aa76d8e9c5d758febd4f9f7dab016aaeb2aefd5b3fc0edc62 085ba3cc4b401f2c6af8579959155313136ea4d1361f2bc14541188dba0bbf6a structures/environment.dto.js
853308109c1a7dbbe4798c943bd578016d93bcb2f5a7727e3b18374bf749b97d 83be1f3d8b2f8194da698afd8d782969ec93575e1bb2777f2b999e8099ed5c52 utils/bull/BaseWorkerHost.js
91859392794b5bfdfd633e7dce77a3749b0e8d8216d949493f15801ec2730e38 c8fa8d6004c76279a46e31bb2992ef52753e518ad865377a6592f6f234d60b61 version.js
NEW d9cb32f335bb638299ca8c10cd745848f0578e2e65490ffca4d25f37e3421dad apps/chatwoot/api/c2y.signature.js
NEW c9440d517c67120480a4caf47d078fe4362693b093a7de856a3ac6201e809fc8 apps/chatwoot/api/rawbody.js
NEW 5ad164eb05c7a0e202e3355077a8a95da00812459501931e6068aa0ee7bceaca apps/chatwoot/consumers/inbox/c2y_actions.js
NEW 4c1b15efeb1f810dec2fd54643f617237334e0134b34ba14c51a14c449b5f641 apps/chatwoot/consumers/waha/event.response.js
NEW fd72feabdc6afbed81c9eed56ee70085971bc24522c22acfa92b69db0c63252f apps/chatwoot/consumers/waha/poll.vote.js
NEW affdefe44c42cc9947e50dd11f27c828b10e6bacb28657ed536000b8d9d66362 apps/chatwoot/consumers/waha/view_once.unavailable.js
NEW b6a3db7cdc83975140c496e968714b93c91e0c21976814236db204446772971b apps/chatwoot/messages/to/chatwoot/ListReply.js
NEW 47582d74883edf1862708346e513cffc9ad23c7e1b97100c1deeb031b79374a4 apps/chatwoot/messages/to/chatwoot/UnknownContentType.js
NEW 0277ee22bde52f042f63b76fdc433fce6244825587b0d0b8c8163f7d090f4c57 apps/chatwoot/messages/to/chatwoot/ViewOnceNotice.js
NEW 28b4e56f787edd498836e896e5cce38a0b49161861c18752549900f56d4c2b5c apps/chatwoot/messages/to/chatwoot/c2y3.js
NEW c81af9f0fa253dd7802c790a6522183d6e76544cce2fcbb634a2717b43059768 apps/chatwoot/messages/to/chatwoot/c2y3.retry.js
NEW 40b25e2d5d73fa86e396c2af6dbf1ba0ac5adc7fc034eaf7b23726766fd55529 apps/chatwoot/messages/to/whatsapp/actions.js
NEW fe861eb58082bf9a993a9ea9a83ff06a16a86066b83867e489630e99c32a458a apps/chatwoot/messages/to/whatsapp/hints.js
NEW 5a2d42b790708336f2547b63e49a0c10b3c534f54b1942cfac361a2b378d88f4 apps/chatwoot/messages/to/whatsapp/media.js
NEW 640d45ab948407cabdb9d68337aa00ca61c1156cd9bbb23dc05dde4a8e8c2701 apps/chatwoot/messages/to/whatsapp/native.js
NEW 11cbf501f3205f6e1e9e758afc9928f92b61a644875927297b5159e7e72d2622 core/engines/gows/c2y.viewonce.js
EOF
)

# The file and, for JS, its source map
with_map() {
  if [[ "$1" == *.js ]]; then printf '%s\n%s\n' "$1" "$1.map"; else printf '%s\n' "$1"; fi
}

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
    while read -r f; do
      [[ -f "$DIST_DIR/$f" ]] || fail "missing in dist: $f" 5
      mkdir -p "$(dirname "$STAGE/$f")"
      cp "$DIST_DIR/$f" "$STAGE/$f"
    done < <(with_map "$file")
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
    while read -r f; do
      copy_from_container "$builder_cid" "/git/dist/$f" "$STAGE/$f" || fail "builder did not produce dist/$f" 5
    done < <(with_map "$file")
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
# 3. Overlay: only the changed files (JS + .map, locale YAML), nothing else (FROM, COPY, LABEL - no RUN)
#
echo "[3/5] Building overlay $IMAGE_TAG ($PLATFORM, no pull)"
{
  echo "FROM $BASE_LOCAL"
  while read -r _before _after file; do
    [[ -n "$file" ]] || continue
    while read -r f; do
      echo "COPY dist/$f /app/dist/$f"
    done < <(with_map "$file")
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
  expected_ext='"autonomia":{"patch":"c2y-rich-4","rich_native":["options","location","contact","poll","link_button","event"],"list_reply":true,"poll_vote":true,"reactions":true,"edit":true,"media_as_media":true,"format":"c2y-1","event_response":true,"view_once_notice":true}'
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
