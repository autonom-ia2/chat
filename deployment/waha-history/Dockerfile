FROM devlikeapro/waha-plus@sha256:ac5d6c131155df16e4a29c29efdbdf977788a0a4908dbe9d8edf4366202e9598

# Build with deployment/waha-history as the context. The patch only replaces
# the pinned compiled artifacts below; no WAHA PLUS source tree is copied.
COPY patch.cjs /tmp/chat2you-waha-history-patch.cjs
RUN node /tmp/chat2you-waha-history-patch.cjs --self-test / \
    && node /tmp/chat2you-waha-history-patch.cjs / \
    && rm /tmp/chat2you-waha-history-patch.cjs
