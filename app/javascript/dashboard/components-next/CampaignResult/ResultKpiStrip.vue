<script setup>
// Summary band of a result (#1007, PRD §7): first number on navy, the others in a grid.
// item: { key, label, value, display?, note?, details?: [{ key, label, value }] }
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

defineProps({
  items: { type: Array, required: true },
  label: { type: String, required: true },
});

const { t, locale } = useI18n();
const openDetails = ref('');

const format = value =>
  typeof value === 'number'
    ? new Intl.NumberFormat(locale.value.replace('_', '-')).format(value)
    : '—';

const toggle = key => {
  openDetails.value = openDetails.value === key ? '' : key;
};
</script>

<template>
  <section
    class="flex flex-col overflow-hidden rounded-3xl border border-n-weak bg-n-solid-1 shadow-sm lg:flex-row"
    :aria-label="label"
    data-kpi-strip
  >
    <div
      v-if="items.length"
      class="min-w-0 bg-n-navy px-6 py-6 text-white lg:w-[22%]"
      :data-kpi="items[0].key"
    >
      <p class="mb-0 text-xs text-white opacity-80">{{ items[0].label }}</p>
      <p class="mb-0 mt-3 text-3xl font-semibold tabular-nums tracking-tight">
        {{ items[0].display ?? format(items[0].value) }}
      </p>
      <p v-if="items[0].note" class="mb-0 mt-2 text-xs text-white opacity-80">
        {{ items[0].note }}
      </p>
    </div>
    <dl
      class="m-0 grid min-w-0 flex-1 grid-cols-2 gap-x-5 gap-y-6 px-6 py-6 sm:grid-cols-3 xl:grid-cols-4"
    >
      <div
        v-for="item in items.slice(1)"
        :key="item.key"
        class="min-w-0"
        :data-kpi="item.key"
      >
        <dt class="text-xs text-n-slate-11">{{ item.label }}</dt>
        <dd
          class="m-0 mt-1.5 text-2xl font-semibold tabular-nums text-n-slate-12"
        >
          {{ item.display ?? format(item.value) }}
        </dd>
        <dd v-if="item.note" class="m-0 mt-1 text-xs text-n-slate-11">
          {{ item.note }}
        </dd>
        <dd v-if="item.details?.length" class="m-0 mt-1">
          <button
            type="button"
            class="inline-flex min-h-11 items-center gap-1 text-xs font-medium text-n-blue-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :aria-expanded="openDetails === item.key"
            data-kpi-details-toggle
            @click="toggle(item.key)"
          >
            {{ t('RESULT_JOURNEY.KPI.DETAILS') }}
            <span
              :class="
                openDetails === item.key
                  ? 'i-lucide-chevron-up'
                  : 'i-lucide-chevron-down'
              "
              class="size-3.5"
              aria-hidden="true"
            />
          </button>
          <dl
            v-show="openDetails === item.key"
            class="m-0 flex flex-col gap-1 text-xs"
            data-kpi-details
          >
            <div v-for="detail in item.details" :key="detail.key">
              <dt class="text-n-slate-11">{{ detail.label }}</dt>
              <dd class="m-0 font-medium text-n-slate-12">
                {{ format(detail.value) }}
              </dd>
            </div>
          </dl>
        </dd>
      </div>
    </dl>
  </section>
</template>
