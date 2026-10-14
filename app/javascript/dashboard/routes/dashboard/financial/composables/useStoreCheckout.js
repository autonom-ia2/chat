import { inject, onScopeDispose, ref } from 'vue';
import StoreAPI from 'dashboard/api/autonomia/store';
import {
  clearCheckoutIntent,
  readCheckoutIntent,
  writeCheckoutIntent,
} from '../helpers/storeCheckout';

export function useStoreCheckout(scopeKey) {
  const submitting = ref(false);
  const errorCode = ref('');
  const navigate = inject('storeCheckoutNavigate', url =>
    window.location.assign(url)
  );
  let disposed = false;
  let generation = 0;
  onScopeDispose(() => {
    disposed = true;
  });

  const start = async priceId => {
    if (submitting.value) return undefined;
    const current = generation;
    const key = scopeKey.value;
    submitting.value = true;
    errorCode.value = '';
    try {
      let intent = readCheckoutIntent(key);
      if (intent && intent.priceId !== priceId) {
        errorCode.value = 'PENDING_OTHER_PLAN';
        return undefined;
      }
      let response;
      if (intent) {
        try {
          response = await StoreAPI.resolveCheckout(intent.clientIntent);
        } catch (failure) {
          if (failure.response?.status !== 404) throw failure;
        }
      } else {
        intent = { clientIntent: crypto.randomUUID(), priceId };
        writeCheckoutIntent(key, intent);
      }
      if (disposed || scopeKey.value !== key) return undefined;
      if (!response) {
        response = await StoreAPI.checkout({
          clientIntent: intent.clientIntent,
          servicePlanPriceId: priceId,
          limits: [],
        });
      }
      if (disposed || scopeKey.value !== key) return undefined;
      const result = response.data;
      writeCheckoutIntent(key, { ...intent, operationId: result.operation.id });
      if (current !== generation) return undefined;
      if (result.operation.state === 'completed') {
        clearCheckoutIntent(key, result.operation.id);
        return result.operation;
      }
      if (result.operation.canStartNewCheckout) {
        clearCheckoutIntent(key, result.operation.id, intent.clientIntent);
        errorCode.value = 'CHECKOUT_ENDED';
        return result.operation;
      }
      if (result.checkoutUrl) {
        const url = new URL(result.checkoutUrl);
        if (url.protocol !== 'https:' || url.username || url.password)
          throw new Error('Invalid checkout URL.');
        navigate(url.href, result.operation.id);
      } else {
        errorCode.value = 'CHECKOUT_PENDING';
      }
      return result.operation;
    } catch (failure) {
      if (!disposed && scopeKey.value === key) {
        if (failure.response?.status === 401)
          errorCode.value = 'SESSION_EXPIRED';
        else if (failure.response?.data?.code === 'SERVICE_ALREADY_CONTRACTED')
          errorCode.value = 'ALREADY_CONTRACTED';
        else errorCode.value = 'CHECKOUT_ERROR';
      }
      return undefined;
    } finally {
      submitting.value = false;
    }
  };
  const stop = () => {
    generation += 1;
  };
  const resumePending = async () => {
    try {
      const intent = readCheckoutIntent(scopeKey.value);
      return intent ? await start(intent.priceId) : undefined;
    } catch {
      errorCode.value = 'CHECKOUT_ERROR';
      return undefined;
    }
  };
  return { start, submitting, errorCode, stop, resumePending };
}
