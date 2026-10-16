<script setup>
import { computed, nextTick, ref, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useLocale } from 'shared/composables/useLocale';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StoreAPI from 'dashboard/api/autonomia/store';
import { useStoreLabels } from '../composables/useStoreLabels';
import { useStoreSubscriptionCommand } from '../composables/useStoreSubscriptionCommand';

const emit = defineEmits(['changed']);
const { t } = useI18n();
const route = useRoute();
const labels = useStoreLabels();
const { resolvedLocale } = useLocale();
const dialog = useTemplateRef('dialog');
const confirmation = useTemplateRef('confirmation');
const entry = ref(null);
const capability = ref(null);
const intent = ref('');
const loadError = ref('');
const confirmed = ref(false);
const { run, abort, isPending } = useAbortableRequest();
const load = async control => {
  capability.value = null;
  loadError.value = '';
  control.stop();
  control.operation.value = null;
  control.errorCode.value = '';
  intent.value = crypto.randomUUID();
  try {
    const response = await run(signal =>
      StoreAPI.cancellationCapability(entry.value.subscription.id, signal)
    );
    if (!response) return;
    capability.value = response.data.data;
    control.operation.value = response.data.localCommand;
  } catch (failure) {
    loadError.value =
      failure.response?.status === 401 ? 'SESSION_EXPIRED' : 'LOAD_ERROR';
  }
};
const command = useStoreSubscriptionCommand(async result => {
  if (result.state !== 'confirmed') return;
  confirmed.value = true;
  await load(command);
  await nextTick();
  confirmation.value?.focus();
  emit('changed');
});
const { operation, busy, errorCode } = command;
const action = computed(() =>
  capability.value?.canResume ? 'resume' : 'schedule'
);
const allowed = computed(() =>
  action.value === 'resume'
    ? capability.value?.canResume
    : capability.value?.canSchedule
);
const until = computed(() =>
  capability.value?.accessUntil
    ? new Intl.DateTimeFormat(resolvedLocale.value, {
        dateStyle: 'medium',
        timeStyle: 'short',
      }).format(new Date(capability.value.accessUntil))
    : null
);
const open = async value => {
  entry.value = value;
  confirmed.value = false;
  dialog.value.open();
  await load(command);
};
const confirm = () => {
  if (!allowed.value || busy.value || operation.value || isPending.value)
    return;
  command.execute(() =>
    StoreAPI.subscriptionCommand(entry.value.subscription.id, action.value, {
      clientIntent: intent.value,
      expectedVersion: capability.value.subscriptionVersion,
    })
  );
};
const close = () => {
  abort();
  command.stop();
};
watch(
  () => route.params.accountId,
  () => {
    close();
    dialog.value?.close();
  }
);
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('FINANCIAL.STORE.CANCELLATION.TITLE')"
    :confirm-button-label="
      action === 'resume'
        ? t('FINANCIAL.STORE.CANCELLATION.RESUME')
        : t('FINANCIAL.STORE.CANCELLATION.SCHEDULE')
    "
    :cancel-button-label="t('FINANCIAL.STORE.CLOSE')"
    :disable-confirm-button="
      !allowed || busy || isPending || Boolean(operation)
    "
    :is-loading="busy"
    width="lg"
    overflow-y-auto
    @confirm="confirm"
    @close="close"
  >
    <div class="flex flex-col min-w-0 max-h-[55dvh] gap-4 overflow-y-auto">
      <h3 class="m-0 text-base font-medium break-words text-n-slate-12">
        {{ entry?.service.name }}
      </h3>
      <Spinner v-if="isPending" />
      <template v-if="capability">
        <p class="m-0 text-sm text-n-slate-12">
          {{ labels.renewal[capability.renewalState] }}
        </p>
        <p v-if="until" class="m-0 text-sm text-n-slate-11">
          {{ t('FINANCIAL.STORE.CANCELLATION.ACCESS_UNTIL', { date: until }) }}
        </p>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('FINANCIAL.STORE.CANCELLATION.SCOPE') }}
        </p>
        <p
          v-if="capability.blockingReason"
          role="alert"
          class="m-0 text-sm text-n-ruby-11"
        >
          {{ labels.cancellationBlockers[capability.blockingReason] }}
        </p>
      </template>
      <p
        v-if="loadError || errorCode"
        role="alert"
        class="m-0 text-sm text-n-ruby-11"
      >
        {{ labels.errors[loadError || errorCode] }}
      </p>
      <p
        v-if="confirmed"
        ref="confirmation"
        role="status"
        tabindex="-1"
        class="m-0 text-sm text-n-slate-12"
      >
        {{ t('FINANCIAL.STORE.CANCELLATION.CONFIRMED') }}
      </p>
      <p
        v-if="operation?.state === 'pending'"
        role="status"
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t('FINANCIAL.STORE.COMMAND_PENDING') }}
      </p>
      <div class="flex flex-wrap gap-2">
        <Button
          v-if="operation?.state === 'pending'"
          :label="t('FINANCIAL.STORE.CANCELLATION.RETRY_COMMAND')"
          icon="i-lucide-refresh-cw"
          :disabled="busy || isPending"
          variant="ghost"
          @click="command.execute(() => StoreAPI.retryCommand(operation.id))"
        />
        <Button
          :label="t('FINANCIAL.REFRESH')"
          icon="i-lucide-refresh-cw"
          variant="ghost"
          :disabled="busy || isPending"
          @click="load(command)"
        />
      </div>
    </div>
  </Dialog>
</template>
