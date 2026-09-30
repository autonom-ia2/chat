<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import axios from 'dashboard/api/relationships';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  entity: {
    type: String,
    required: true,
    validator: value => ['contacts', 'companies'].includes(value),
  },
});
const { t, locale } = useI18n();
const { accountId, isCloudFeatureEnabled } = useAccount();
const summary = ref(null);
const loading = ref(false);
const error = ref(false);
let generation = 0;
const metrics = computed(() => [
  {
    key: 'total',
    icon:
      props.entity === 'contacts' ? 'i-lucide-users' : 'i-lucide-building-2',
  },
  { key: 'new_in_period', icon: 'i-lucide-user-round-plus' },
  {
    key: props.entity === 'contacts' ? 'active_in_period' : 'with_contacts',
    icon: 'i-lucide-messages-square',
  },
  ...(props.entity === 'companies' || isCloudFeatureEnabled('companies')
    ? [
        {
          key:
            props.entity === 'contacts' ? 'with_company' : 'inactive_in_period',
          icon:
            props.entity === 'contacts' ? 'i-lucide-link' : 'i-lucide-history',
        },
      ]
    : []),
]);
const number = value =>
  new Intl.NumberFormat(locale.value.replaceAll('_', '-')).format(value);
const load = async () => {
  generation += 1;
  const current = generation;
  summary.value = null;
  loading.value = true;
  error.value = false;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/${props.entity}/summary`
    );
    if (current === generation) summary.value = data;
  } catch {
    if (current === generation) error.value = true;
  } finally {
    if (current === generation) loading.value = false;
  }
};
watch(() => [accountId.value, props.entity], load, {
  immediate: true,
  flush: 'sync',
});
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section class="my-6" :aria-busy="loading">
    <header class="mb-3 flex flex-wrap items-center justify-between gap-2">
      <h2 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('RELATIONSHIPS.SUMMARY.TITLE') }}
      </h2>
      <span class="flex items-center gap-2 text-xs text-n-slate-11">
        <span class="i-lucide-calendar-days size-4" aria-hidden="true" />
        {{ t('RELATIONSHIPS.SUMMARY.PERIOD') }}
      </span>
    </header>
    <div
      v-if="error"
      role="alert"
      class="flex flex-wrap items-center gap-3 rounded-3xl border border-n-weak bg-n-solid-2 px-6 py-5 text-sm text-n-slate-11"
    >
      {{ t('RELATIONSHIPS.SUMMARY.ERROR') }}
      <Button ghost slate sm :label="t('RELATIONSHIPS.RETRY')" @click="load" />
    </div>
    <dl
      v-else
      class="m-0 grid grid-cols-2 overflow-hidden rounded-3xl border border-n-blue-5 bg-n-solid-2 shadow-sm xl:grid-cols-4"
    >
      <div
        v-for="(metric, index) in metrics"
        :key="metric.key"
        class="flex min-w-0 flex-col justify-between gap-5 p-5 md:p-6"
        :class="[
          index === 0
            ? 'bg-gradient-to-br from-n-blue-3 to-n-blue-2'
            : 'border-s border-n-weak',
          index > 1 ? 'border-t xl:border-t-0' : '',
          index === 2 ? 'border-s-0 xl:border-s' : '',
        ]"
      >
        <dt
          class="flex flex-col items-start gap-3 text-sm font-medium leading-5 sm:flex-row sm:items-center"
        >
          <span
            class="flex size-10 shrink-0 items-center justify-center rounded-full text-n-blue-11"
            :class="index === 0 ? 'bg-n-solid-2' : 'bg-n-blue-3'"
            aria-hidden="true"
          >
            <span :class="metric.icon" class="size-5" />
          </span>
          <span :class="index === 0 ? 'text-n-blue-12' : 'text-n-slate-11'">
            {{ t(`RELATIONSHIPS.SUMMARY.${entity}.${metric.key}`) }}
          </span>
        </dt>
        <dd class="m-0">
          <span
            class="block text-3xl font-semibold leading-none tracking-tight tabular-nums md:text-4xl"
            :class="index === 0 ? 'text-n-blue-12' : 'text-n-slate-12'"
          >
            {{
              summary
                ? number(summary[metric.key])
                : t('RELATIONSHIPS.SUMMARY.PENDING')
            }}
          </span>
          <span class="mt-3 block text-xs leading-5 text-n-slate-11">
            {{
              t(`RELATIONSHIPS.SUMMARY.DESCRIPTIONS.${entity}.${metric.key}`)
            }}
          </span>
        </dd>
      </div>
    </dl>
  </section>
</template>
