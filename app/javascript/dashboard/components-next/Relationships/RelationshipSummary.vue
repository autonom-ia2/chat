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
  { key: 'new_in_period', icon: 'i-lucide-plus' },
  {
    key: props.entity === 'contacts' ? 'active_in_period' : 'with_contacts',
    icon: 'i-lucide-messages-square',
  },
  ...(props.entity === 'companies' || isCloudFeatureEnabled('companies')
    ? [
        {
          key:
            props.entity === 'contacts' ? 'with_company' : 'inactive_in_period',
          icon: 'i-lucide-link',
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
  <section
    class="my-5 overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2"
    :aria-busy="loading"
  >
    <header
      class="flex flex-wrap items-center justify-between gap-2 border-b border-n-weak px-5 py-3"
    >
      <h2 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('RELATIONSHIPS.SUMMARY.TITLE') }}
      </h2>
      <span class="text-xs text-n-slate-11">{{
        t('RELATIONSHIPS.SUMMARY.PERIOD')
      }}</span>
    </header>
    <div
      v-if="error"
      role="alert"
      class="flex flex-wrap items-center gap-3 px-5 py-4 text-sm text-n-slate-11"
    >
      {{ t('RELATIONSHIPS.SUMMARY.ERROR') }}
      <Button ghost slate sm :label="t('RELATIONSHIPS.RETRY')" @click="load" />
    </div>
    <dl
      v-else
      class="m-0 grid grid-cols-1 divide-y divide-n-weak sm:grid-cols-2 xl:grid-cols-4 xl:divide-y-0"
    >
      <div
        v-for="metric in metrics"
        :key="metric.key"
        class="flex min-w-0 items-center gap-3 px-5 py-5"
      >
        <span
          class="flex size-11 shrink-0 items-center justify-center rounded-full bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          <span :class="metric.icon" class="size-5" />
        </span>
        <div class="min-w-0">
          <dt class="text-xs text-n-slate-11">
            {{ t(`RELATIONSHIPS.SUMMARY.${entity}.${metric.key}`) }}
          </dt>
          <dd
            class="m-0 mt-1 text-2xl font-semibold tabular-nums text-n-slate-12"
          >
            {{
              summary
                ? number(summary[metric.key])
                : t('RELATIONSHIPS.SUMMARY.PENDING')
            }}
          </dd>
        </div>
      </div>
    </dl>
  </section>
</template>
