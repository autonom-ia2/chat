import { onScopeDispose, ref } from 'vue';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import StoreAPI from 'dashboard/api/autonomia/store';

const POLL_INTERVAL_MS = 5000;
const MAX_POLLS = 12;
const errorLabel = code => {
  if (code === 'UNAUTHORIZED') return 'SESSION_EXPIRED';
  if (code === 'CONFLICT') return 'COMMAND_CONFLICT';
  return 'COMMAND_PENDING';
};

export function useStoreSubscriptionCommand(onSettled) {
  const operation = ref(null);
  const busy = ref(false);
  const errorCode = ref('');
  const { run, abort } = useAbortableRequest();
  let generation = 0;
  let timer;
  const stop = () => {
    generation += 1;
    clearTimeout(timer);
    abort();
    busy.value = false;
  };
  const follow = async (id, epoch, remaining = MAX_POLLS) => {
    try {
      const response = await run(signal => StoreAPI.commandStatus(id, signal));
      if (!response || generation !== epoch) return;
      operation.value = response.data.data;
      if (operation.value.state !== 'pending') {
        busy.value = false;
        errorCode.value =
          operation.value.state === 'blocked'
            ? errorLabel(operation.value.errorCode)
            : '';
        await onSettled(operation.value);
      } else if (!remaining || operation.value.errorCode) {
        busy.value = false;
        errorCode.value = errorLabel(operation.value.errorCode);
      } else {
        timer = setTimeout(
          () => follow(id, epoch, remaining - 1),
          POLL_INTERVAL_MS
        );
      }
    } catch (failure) {
      if (generation !== epoch) return;
      busy.value = false;
      errorCode.value =
        failure.response?.status === 401
          ? 'SESSION_EXPIRED'
          : 'COMMAND_PENDING';
    }
  };
  const execute = async action => {
    stop();
    const epoch = generation;
    busy.value = true;
    errorCode.value = '';
    try {
      const response = await action();
      if (epoch !== generation) return;
      operation.value = response.data.data;
      await follow(operation.value.id, epoch);
    } catch (failure) {
      if (epoch !== generation) return;
      busy.value = false;
      errorCode.value = 'COMMAND_PENDING';
      if (failure.response?.status === 401) errorCode.value = 'SESSION_EXPIRED';
      if (failure.response?.status === 409)
        errorCode.value = 'COMMAND_CONFLICT';
    }
  };
  onScopeDispose(stop);
  return { operation, busy, errorCode, stop, execute };
}
