<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import StoreAPI from 'dashboard/api/autonomia/store';
import { useStoreActivation } from '../composables/useStoreActivation';
import { useStoreLabels } from '../composables/useStoreLabels';

const emit = defineEmits(['changed']);
const { t } = useI18n();
const labels = useStoreLabels();
const route = useRoute();
const store = useStore();
const dialog = useTemplateRef('dialog');
const entry = ref(null);
const accounts = ref([]);
const selected = ref(null);
const intent = ref('');
const loadingError = ref(false);
const { run, abort, isPending } = useAbortableRequest();
const operationControl = useStoreActivation(async result => {
  emit('changed');
  if (result.accountId === Number(route.params.accountId))
    await store.dispatch('accounts/get', {
      silent: true,
      accountId: result.accountId,
    });
});
const { operation, busy, errorCode } = operationControl;
const options = computed(() =>
  accounts.value.map(account => ({ value: account.id, label: account.name }))
);
const open = async value => {
  entry.value = value;
  intent.value = crypto.randomUUID();
  selected.value = null;
  accounts.value = [];
  loadingError.value = false;
  operationControl.stop();
  operation.value = null;
  errorCode.value = '';
  dialog.value.open();
  try {
    const result = await run(signal => StoreAPI.eligibleAccounts(signal));
    if (!result) return;
    accounts.value = result.data.data;
    selected.value =
      accounts.value.find(
        account => account.id === Number(route.params.accountId)
      )?.id ||
      accounts.value[0]?.id ||
      null;
  } catch {
    loadingError.value = true;
  }
};
const confirm = () => {
  if (!selected.value || busy.value) return;
  operationControl.execute(() =>
    StoreAPI.activate({
      serviceSubscriptionId: entry.value.subscription.id,
      accountId: selected.value,
      clientIntent: intent.value,
    })
  );
};
const close = () => {
  abort();
  operationControl.stop();
};
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('FINANCIAL.STORE.ACTIVATE_TITLE')"
    :confirm-button-label="t('FINANCIAL.STORE.ACTIVATE')"
    :cancel-button-label="t('FINANCIAL.STORE.CLOSE')"
    :disable-confirm-button="
      !selected || busy || isPending || Boolean(operation)
    "
    :is-loading="busy"
    width="lg"
    overflow-y-auto
    @confirm="confirm"
    @close="close"
  >
    <div class="flex flex-col min-w-0 max-h-[55dvh] gap-4 overflow-y-auto">
      <p class="m-0 font-medium text-n-slate-12">{{ entry?.service.name }}</p>
      <label class="flex flex-col min-w-0 gap-2 text-sm text-n-slate-12">
        {{ t('FINANCIAL.STORE.ACCOUNT') }}
        <ChoiceSelect
          v-model="selected"
          :options="options"
          :disabled="busy || Boolean(operation)"
          :aria-label="t('FINANCIAL.STORE.ACCOUNT')"
        />
      </label>
      <p v-if="loadingError" role="alert" class="text-sm text-n-ruby-11">
        {{ t('FINANCIAL.STORE.LOAD_ERROR') }}
      </p>
      <p
        v-else-if="!isPending && !accounts.length"
        class="text-sm text-n-slate-11"
      >
        {{ t('FINANCIAL.STORE.NO_ELIGIBLE_ACCOUNTS') }}
      </p>
      <p v-if="operation" role="status" class="m-0 text-sm text-n-slate-12">
        {{
          labels.activation[
            operation.state === 'ready' && !operation.available
              ? 'suspended'
              : operation.state
          ]
        }}
      </p>
      <p v-if="errorCode" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ labels.errors[errorCode] }}
      </p>
      <Button
        v-if="operation && errorCode && operation.state !== 'failed'"
        :label="t('FINANCIAL.STORE.PUBLICATION.RETRY')"
        icon="i-lucide-refresh-cw"
        variant="ghost"
        :disabled="busy"
        @click="
          operationControl.execute(() =>
            StoreAPI.resumeActivation(operation.id)
          )
        "
      />
    </div>
  </Dialog>
</template>
