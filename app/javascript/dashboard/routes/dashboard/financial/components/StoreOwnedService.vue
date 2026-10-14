<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import Button from 'dashboard/components-next/button/Button.vue';
import StoreServiceIcon from './StoreServiceIcon.vue';
import { formatMoney, subscriptionStatusLabel } from '../helpers';
import { canActivateStoreEntry } from '../helpers/storeCheckout';
import { useStoreLabels } from '../composables/useStoreLabels';

const props = defineProps({
  busy: { type: Boolean, default: false },
  entry: { type: Object, required: true },
  activations: { type: Array, default: () => [] },
  accounts: { type: Array, default: () => [] },
});
defineEmits(['activate', 'deactivate', 'resume', 'renewal']);
const { t } = useI18n();
const router = useRouter();
const labels = useStoreLabels();
const { resolvedLocale } = useLocale();
const eligible = computed(() => canActivateStoreEntry(props.entry));
const owned = computed(() =>
  props.activations.filter(
    value => value.serviceSubscriptionId === props.entry.subscription.id
  )
);
const accountName = id =>
  props.accounts.find(value => value.id === id)?.name ||
  t('FINANCIAL.STORE.ACCOUNT_ID', { id });
</script>

<template>
  <article
    class="flex flex-col min-w-0 gap-4 p-4 border rounded-lg border-n-weak bg-n-solid-1"
  >
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div class="flex min-w-0 gap-3">
        <StoreServiceIcon
          :item="{ service: entry.service, group: entry.target.type }"
        />
        <div class="min-w-0">
          <h3 class="m-0 text-base font-medium break-words text-n-slate-12">
            {{ entry.service.name }}
          </h3>
          <span class="text-sm text-n-slate-11">{{
            subscriptionStatusLabel(t, entry.subscription.status)
          }}</span>
        </div>
      </div>
      <Button
        :label="t('FINANCIAL.STORE.ACTIVATE')"
        icon="i-lucide-plus"
        :disabled="!eligible || busy"
        @click="$emit('activate', entry)"
      />
    </header>
    <p class="m-0 text-sm text-n-slate-11">
      {{ entry.plan.name }} {{ labels.separator }}
      {{ formatMoney(entry.price.price, entry.price.currency, resolvedLocale) }}
      {{ labels.cycles[entry.price.billingCycle] }}
    </p>
    <dl class="m-0 divide-y divide-n-weak">
      <div
        v-for="limit in entry.subscription.limits"
        :key="limit.metricKey"
        class="flex flex-wrap justify-between gap-2 py-2 text-sm"
      >
        <dt class="min-w-0 text-n-slate-12">
          {{ limit.metricName
          }}<span class="block text-xs text-n-slate-11">{{
            labels.usage[limit.usageBehavior]
          }}</span>
        </dt>
        <dd class="m-0 text-n-slate-11">
          {{
            t('FINANCIAL.STORE.USAGE_TOTAL', {
              used: limit.usedQuantity,
              total: limit.contractedQuantity,
              unit: limit.unit,
            })
          }}
        </dd>
      </div>
    </dl>
    <Button
      :label="t('FINANCIAL.STORE.CANCELLATION.TITLE')"
      icon="i-lucide-calendar-clock"
      variant="ghost"
      :disabled="busy"
      @click="$emit('renewal', entry)"
    />
    <ul v-if="owned.length" class="p-0 m-0 list-none divide-y divide-n-weak">
      <li
        v-for="activation in owned"
        :key="activation.id"
        class="flex flex-wrap items-center justify-between gap-3 py-3"
      >
        <div class="min-w-0 text-sm text-n-slate-12">
          {{ accountName(activation.accountId) }}
          <span class="block text-xs text-n-slate-11">{{
            labels.activation[
              activation.state === 'ready' && !activation.available
                ? 'suspended'
                : activation.state
            ]
          }}</span>
          <p
            v-if="activation.errorCode === 'RESERVATION_EXPIRED'"
            class="m-0 text-xs text-n-slate-11"
          >
            {{ labels.errors.RESERVATION_EXPIRED }}
          </p>
        </div>
        <div class="flex gap-2">
          <Button
            v-if="activation.agentId && activation.available"
            icon="i-lucide-settings-2"
            :label="t('AGENTS.CONTRACTED.CONFIGURE')"
            variant="ghost"
            @click="
              router.push({
                name: 'autonomia_agent_panel',
                params: {
                  accountId: activation.accountId,
                  agentId: activation.agentId,
                  tab: 'tune',
                },
              })
            "
          />
          <Button
            v-if="
              activation.state !== 'failed' &&
              (activation.errorCode ||
                (activation.state === 'ready' && !activation.available))
            "
            icon="i-lucide-refresh-cw"
            :aria-label="t('FINANCIAL.STORE.PUBLICATION.RETRY')"
            variant="ghost"
            color="slate"
            :disabled="busy"
            @click="$emit('resume', activation)"
          />
          <Button
            v-if="activation.state !== 'disabled'"
            :label="t('FINANCIAL.STORE.DEACTIVATE')"
            icon="i-lucide-power"
            variant="ghost"
            color="slate"
            :disabled="busy"
            @click="$emit('deactivate', activation)"
          />
        </div>
      </li>
    </ul>
  </article>
</template>
