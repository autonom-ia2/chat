FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server sudo python3 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && printf '%s\n' synthetic-only > /run/instagram-publisher-synthetic-fixture
COPY scripts/instagram_testers/runtime/forced-publisher.sh scripts/instagram_testers/runtime/install-remote-publisher.sh /fixture/runtime/
COPY tests/instagram_testers/fixtures/remote-publisher-sudo/fake-docker.py /usr/bin/docker
COPY tests/instagram_testers/remote-publisher-sudo_smoke.py /fixture/smoke.py
RUN chmod 755 /usr/bin/docker /fixture/runtime/*.sh
ENTRYPOINT ["python3", "-B", "/fixture/smoke.py"]
