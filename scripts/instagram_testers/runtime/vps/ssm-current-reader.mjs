const INSTANCE_ID = /^i-[0-9a-f]{8,17}$/;
const PARAMETER_NAME = '/chatwoot/prod/blue-green/current-instance-id';

const staticFailure = () => new Error('instagram_session_publication_failed');

function requireSafe(value) {
  if (!value) throw staticFailure();
  return value;
}

function abortSignal({ signal, timeoutMs, onAbort } = {}) {
  const controller = new AbortController();
  let timer;
  const abort = () => {
    controller.abort();
    onAbort?.();
  };
  signal?.addEventListener('abort', abort, { once: true });
  if (Number.isInteger(timeoutMs) && timeoutMs > 0)
    timer = setTimeout(abort, timeoutMs);
  if (signal?.aborted) abort();
  return {
    signal: controller.signal,
    abort,
    clear() {
      if (timer) clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
    },
  };
}

export async function createSsmCurrentReader(
  config,
  { clientFactory, commandFactory } = {}
) {
  requireSafe(config && typeof config === 'object');
  requireSafe(typeof config.region === 'string' && config.region.length > 0);
  requireSafe(
    typeof config.awsProfile === 'string' && config.awsProfile.length > 0
  );
  requireSafe(config.currentInstanceParameter === PARAMETER_NAME);
  if (!clientFactory || !commandFactory) {
    const sdk = await import('@aws-sdk/client-ssm');
    clientFactory ||= sdk.SSMClient;
    commandFactory ||= sdk.GetParameterCommand;
  }
  const Client = clientFactory;
  const Command = commandFactory;
  const client = new Client({
    region: config.region,
    profile: config.awsProfile,
    maxAttempts: 1,
  });
  let closed = false;
  const activeRequests = new Set();

  return Object.freeze({
    async read({ signal, timeoutMs } = {}) {
      if (closed || signal?.aborted) throw staticFailure();
      let rejectPending;
      const request = abortSignal({
        signal,
        timeoutMs,
        onAbort: () => rejectPending?.(staticFailure()),
      });
      const closedSignal = new Promise((_, reject) => {
        rejectPending = reject;
      });
      activeRequests.add(request);
      try {
        if (request.signal.aborted) throw staticFailure();
        const response = await Promise.race([
          client.send(new Command({ Name: config.currentInstanceParameter }), {
            abortSignal: request.signal,
          }),
          closedSignal,
        ]);
        if (closed || request.signal.aborted || signal?.aborted)
          throw staticFailure();
        const instanceId = response?.Parameter?.Value;
        requireSafe(
          typeof instanceId === 'string' && INSTANCE_ID.test(instanceId)
        );
        return instanceId;
      } catch {
        throw staticFailure();
      } finally {
        request.clear();
        activeRequests.delete(request);
        rejectPending = null;
      }
    },
    close() {
      if (closed) return;
      closed = true;
      activeRequests.forEach(request => {
        request.abort();
      });
      try {
        client.destroy?.();
      } catch {
        // The SDK client is already closed.
      }
    },
  });
}
