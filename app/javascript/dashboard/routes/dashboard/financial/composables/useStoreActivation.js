import { onScopeDispose, ref } from 'vue';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import StoreAPI from 'dashboard/api/autonomia/store';

const POLL_INTERVAL_MS = 5000;
const MAX_POLLS = 12;
const TERMINAL_STATES = ['ready', 'disabled', 'failed'];
const operationError = code => {
  if (code === 'USAGE_LIMIT_EXCEEDED') return 'LIMIT_EXCEEDED';
  if (code === 'RESERVATION_EXPIRED') return 'RESERVATION_EXPIRED';
  return 'ACTIVATION_ERROR';
};

export function useStoreActivation(onSettled) {
  const operation = ref(null);
  const busy = ref(false);
  const errorCode = ref('');
  const { run, abort } = useAbortableRequest();
  let timer;
  let epoch = 0;
  const stop = () => {
    epoch += 1;
    clearTimeout(timer);
    abort();
    busy.value = false;
  };
  const follow = async (id, generation, attempts = 0) => {
    try {
      const response = await run(signal => StoreAPI.activation(id, signal));
      if (!response || epoch !== generation) return;
      operation.value = response.data.data;
      if (operation.value.errorCode)
        errorCode.value = operationError(operation.value.errorCode);
      if (TERMINAL_STATES.includes(operation.value.state)) {
        busy.value = false;
        onSettled(operation.value);
      } else if (attempts >= MAX_POLLS || operation.value.errorCode) {
        busy.value = false;
        errorCode.value ||= 'ACTIVATION_PENDING';
      } else {
        timer = setTimeout(
          () => follow(id, generation, attempts + 1),
          POLL_INTERVAL_MS
        );
      }
    } catch (failure) {
      if (epoch === generation) {
        busy.value = false;
        errorCode.value =
          failure.response?.status === 401
            ? 'SESSION_EXPIRED'
            : operationError(failure.response?.data?.code);
      }
    }
  };
  const execute = async action => {
    stop();
    const generation = epoch;
    busy.value = true;
    errorCode.value = '';
    try {
      const response = await action();
      if (generation !== epoch) return;
      operation.value = response.data.data;
      await follow(operation.value.id, generation);
    } catch (failure) {
      if (generation !== epoch) return;
      busy.value = false;
      errorCode.value =
        failure.response?.status === 401
          ? 'SESSION_EXPIRED'
          : operationError(failure.response?.data?.code);
    }
  };
  onScopeDispose(stop);
  return { operation, busy, errorCode, stop, execute };
}
