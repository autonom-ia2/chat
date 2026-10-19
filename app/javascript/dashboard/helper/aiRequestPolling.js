/* global axios */

const DEFAULT_POLL_INTERVAL_MS = 1000;
const DEFAULT_POLL_TIMEOUT_MS = 30 * 60 * 1000;

const wait = milliseconds =>
  new Promise(resolve => {
    setTimeout(resolve, milliseconds);
  });

const buildPollingError = (code, response) => {
  const error = new Error(code);
  error.code = code;
  if (response) error.response = response;
  return error;
};

// #1872: quem desiste do pedido (descartou, pediu outro) passa um AbortSignal e o poll para.
const throwIfAborted = signal => {
  if (signal?.aborted) throw buildPollingError('ai_request_aborted');
};

const pollUntilSettled = async (
  pollUrl,
  startedAt,
  intervalMs,
  timeoutMs,
  signal
) => {
  throwIfAborted(signal);
  if (Date.now() - startedAt >= timeoutMs) {
    throw buildPollingError('ai_request_timeout');
  }

  await wait(intervalMs);
  throwIfAborted(signal);
  const pollResponse = await (signal
    ? axios.get(pollUrl, { signal })
    : axios.get(pollUrl));
  const { status, result, error: errorCode } = pollResponse.data || {};

  if (status === 'done') return { status: 200, data: result };
  if (status === 'failed') {
    throw buildPollingError(errorCode || 'ai_request_failed', pollResponse);
  }

  return pollUntilSettled(pollUrl, startedAt, intervalMs, timeoutMs, signal);
};

// AI endpoints may return their legacy response or a 202 with a poll URL.
// Keep the response shape expected by existing callers once the job settles.
export const pollAiRequest = async (
  requestPromise,
  {
    intervalMs = DEFAULT_POLL_INTERVAL_MS,
    timeoutMs = DEFAULT_POLL_TIMEOUT_MS,
    signal,
  } = {}
) => {
  const response = await requestPromise;
  throwIfAborted(signal);
  if (!response || response.status !== 202) return response;

  return pollUntilSettled(
    response.data.poll_url,
    Date.now(),
    intervalMs,
    timeoutMs,
    signal
  );
};
