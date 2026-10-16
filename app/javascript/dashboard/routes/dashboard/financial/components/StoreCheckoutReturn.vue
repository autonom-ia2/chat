<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';
import StoreAPI from 'dashboard/api/autonomia/store';
import { clearCheckoutIntent } from '../helpers/storeCheckout';
import { useStoreLabels } from '../composables/useStoreLabels';

const props = defineProps({
  operationId: { type: String, required: true },
  buyerScope: { type: String, required: true },
  cancelled: Boolean,
});
const emit = defineEmits(['confirmed']);
const { t } = useI18n();
const labels = useStoreLabels();
const operation = ref(null);
const error = ref('');
const reconciling = ref(false);
const { run, abort, isPending } = useAbortableRequest();
const terminal = computed(() =>
  ['completed', 'expired', 'failed'].includes(operation.value?.state)
);
let timer;
let generation = 0;
const load = async (attempt = 0) => {
  clearTimeout(timer);
  const current = generation;
  error.value = '';
  if (!/^[0-9a-fA-F-]{36}$/.test(props.operationId)) {
    error.value = 'CHECKOUT_ERROR';
    return;
  }
  try {
    const response = await run(signal =>
      StoreAPI.checkoutStatus(props.operationId, signal)
    );
    if (!response || current !== generation) return;
    operation.value = response.data.operation;
    if (
      operation.value.state === 'completed' ||
      operation.value.canStartNewCheckout
    ) {
      clearCheckoutIntent(
        props.buyerScope,
        operation.value.id,
        operation.value.clientIntent
      );
      if (operation.value.state === 'completed') emit('confirmed');
    } else if (!terminal.value && attempt < 12) {
      timer = setTimeout(() => load(attempt + 1), 5000);
    }
  } catch (failure) {
    if (current === generation)
      error.value =
        failure.response?.status === 401
          ? 'SESSION_EXPIRED'
          : 'CHECKOUT_PENDING';
  }
};
const reconcile = async () => {
  if (reconciling.value || isPending.value) return;
  const current = generation;
  reconciling.value = true;
  try {
    await StoreAPI.reconcileCheckout(props.operationId);
    if (current === generation) await load();
  } catch (failure) {
    if (current === generation)
      error.value =
        failure.response?.status === 401
          ? 'SESSION_EXPIRED'
          : 'CHECKOUT_PENDING';
  } finally {
    if (current === generation) reconciling.value = false;
  }
};
watch(
  [() => props.operationId, () => props.buyerScope],
  () => {
    generation += 1;
    abort();
    operation.value = null;
    reconciling.value = false;
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  clearTimeout(timer);
  abort();
});
</script>

<template>
  <section
    class="flex flex-wrap items-center justify-between gap-3 py-4 border-b border-n-weak"
  >
    <div class="min-w-0 space-y-1">
      <p role="status" class="m-0 text-sm font-medium text-n-slate-12">
        {{ labels.checkout[operation?.state || 'pending'] }}
      </p>
      <p v-if="cancelled && !terminal" class="m-0 text-sm text-n-slate-11">
        {{ t('FINANCIAL.STORE.CHECKOUT_RETURN_CANCEL') }}
      </p>
      <p v-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ labels.errors[error] }}
      </p>
    </div>
    <div v-if="operation?.state !== 'completed'" class="flex flex-wrap gap-2">
      <Button
        :label="t('FINANCIAL.STORE.CHECK_STATUS')"
        icon="i-lucide-refresh-cw"
        variant="ghost"
        :disabled="isPending || reconciling"
        @click="load()"
      />
      <Button
        v-if="!operation?.canStartNewCheckout"
        :label="t('FINANCIAL.STORE.RECONCILE_PAYMENT')"
        icon="i-lucide-search-check"
        variant="ghost"
        :disabled="isPending || reconciling"
        @click="reconcile"
      />
    </div>
  </section>
</template>
