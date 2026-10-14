<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import StoreServiceIcon from './StoreServiceIcon.vue';
import { formatMoney } from '../helpers';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import StoreAPI from 'dashboard/api/autonomia/store';
import { isStorePilot } from '../helpers/storeCheckout';
import { useStoreCheckout } from '../composables/useStoreCheckout';
import { useStoreLabels } from '../composables/useStoreLabels';

const props = defineProps({
  checkoutEnabled: { type: Boolean, default: false },
  buyerScope: { type: String, default: '' },
});
const emit = defineEmits(['owned']);

const { t } = useI18n();
const labels = useStoreLabels();
const { resolvedLocale } = useLocale();
const dialog = useTemplateRef('dialog');
const item = ref(null);
const selectedPrice = ref('');
const existing = ref(false);
const ownershipChecked = ref(false);
const ownershipError = ref(false);
const { run, abort, isPending } = useAbortableRequest();
const pilot = computed(
  () => props.checkoutEnabled && isStorePilot(item.value?.target)
);
const { start, submitting, errorCode, stop, resumePending } = useStoreCheckout(
  computed(() => props.buyerScope)
);
const offer = computed(() =>
  item.value?.offers.find(value => value.price.id === selectedPrice.value)
);
const options = computed(() =>
  (item.value?.offers || []).map(value => ({
    value: value.price.id,
    label: `${value.plan.name} · ${formatMoney(value.price.price, value.price.currency, resolvedLocale.value)} ${labels.value.cycles[value.price.billingCycle]}`,
  }))
);
const open = async value => {
  abort();
  item.value = value;
  selectedPrice.value = value.offers[0]?.price.id || '';
  ownershipChecked.value = false;
  ownershipError.value = false;
  existing.value = false;
  errorCode.value = '';
  dialog.value.open();
  if (!pilot.value) return;
  try {
    const response = await run(signal =>
      StoreAPI.subscriptions(1, signal, value.service.id)
    );
    if (!response) return;
    existing.value = response.data.data.some(entry =>
      ['active', 'trialing'].includes(entry.subscription.status)
    );
    ownershipChecked.value = true;
  } catch {
    ownershipError.value = true;
  }
};
const close = () => {
  stop();
  abort();
  item.value = null;
};
const confirm = async () => {
  if (!pilot.value || !ownershipChecked.value || submitting.value) return;
  if (existing.value) {
    emit('owned');
    dialog.value.close();
    return;
  }
  const result = await start(selectedPrice.value);
  if (result?.state === 'completed') {
    emit('owned');
    dialog.value?.close();
  }
};
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="item?.service.name || ''"
    :show-confirm-button="pilot"
    :confirm-button-label="
      existing
        ? t('FINANCIAL.STORE.OWNED')
        : t('FINANCIAL.STORE.CONTINUE_CHECKOUT')
    "
    :disable-confirm-button="
      !ownershipChecked || isPending || submitting || !selectedPrice
    "
    :is-loading="submitting"
    :cancel-button-label="t('FINANCIAL.STORE.CLOSE')"
    width="xl"
    class="break-words"
    overflow-y-auto
    @close="close"
    @confirm="confirm"
  >
    <div
      v-if="item"
      class="flex flex-col min-w-0 max-h-[60dvh] gap-5 overflow-y-auto"
    >
      <StoreServiceIcon :item="item" />
      <p class="m-0 text-sm break-words text-n-slate-11">
        {{ item.service.description }}
      </p>
      <p v-if="ownershipError" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ t('FINANCIAL.STORE.LOAD_ERROR') }}
      </p>
      <p v-if="errorCode" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ labels.errors[errorCode] }}
      </p>
      <Button
        v-if="errorCode === 'PENDING_OTHER_PLAN'"
        :label="t('FINANCIAL.STORE.RESUME_CHECKOUT')"
        icon="i-lucide-arrow-up-right"
        variant="ghost"
        :disabled="submitting"
        @click="resumePending"
      />
      <Button
        v-if="ownershipError"
        :label="t('FINANCIAL.STORE.PUBLICATION.RETRY')"
        icon="i-lucide-refresh-cw"
        variant="ghost"
        @click="open(item)"
      />
      <label class="flex flex-col min-w-0 gap-2 text-sm text-n-slate-12">
        {{ t('FINANCIAL.STORE.PLAN') }}
        <ChoiceSelect
          v-model="selectedPrice"
          :options="options"
          :aria-label="t('FINANCIAL.STORE.PLAN')"
          class="w-full min-w-0"
          :disabled="submitting"
        />
      </label>
      <section v-if="offer" class="min-w-0">
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t('FINANCIAL.STORE.LIMITS') }}
        </h3>
        <dl class="divide-y divide-n-weak">
          <div
            v-for="limit in offer.limits"
            :key="limit.metricKey"
            class="flex flex-wrap justify-between gap-2 py-3 text-sm"
          >
            <dt class="min-w-0 break-words text-n-slate-12">
              {{ limit.metricName }}
            </dt>
            <dd class="m-0 text-right break-words text-n-slate-11">
              {{ limit.includedQuantity }} {{ limit.unit }}
              <span class="block text-xs">
                {{ labels.usage[limit.usageBehavior] }} {{ labels.separator }}
                {{ labels.reset[limit.resetPeriod] }}
              </span>
            </dd>
          </div>
        </dl>
        <p v-if="!offer.limits.length" class="text-sm text-n-slate-11">
          {{ t('FINANCIAL.STORE.NO_LIMITS') }}
        </p>
      </section>
    </div>
  </Dialog>
</template>
