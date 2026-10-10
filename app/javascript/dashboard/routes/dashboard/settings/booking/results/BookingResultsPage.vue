<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingStatsAPI from 'dashboard/api/crmBookingStats';
import BookingSettingsTabs from '../components/BookingSettingsTabs.vue';
import BookingBackToCalendar from '../components/BookingBackToCalendar.vue';
import ResultsToggle from './ResultsToggle.vue';
import ResultsNumbers from './ResultsNumbers.vue';
import ResultsOrigins from './ResultsOrigins.vue';
import OpenedNotBookedList from './OpenedNotBookedList.vue';
import { DEFAULT_PERIOD, PERIODS, isEmptyTotals } from './resultsFormat';

// Painel de resultados do agendamento (#1194, J7). Duas portas:
// - CRM › Agendamento › Resultados (`entry: 'settings'`): abre na
//   equipe para o administrador e para `agendamento_view`;
// - CRM › Meus números (`entry: 'crm'`): abre nos números da própria pessoa.
// Quem pode ver a equipe troca entre "Só os meus" e "Equipe toda"; o servidor
// decide quem pode (`can_see_team`) e recusa o resto.
const props = defineProps({
  entry: { type: String, default: 'settings' },
});

const { t } = useI18n();
const period = ref(DEFAULT_PERIOD);
const scope = ref(props.entry === 'crm' ? 'mine' : '');
const stats = ref(null);
const loading = ref(true);
const failed = ref(false);

const periodOptions = computed(() =>
  PERIODS.map(days => ({
    value: days,
    label: t(`BOOKING.RESULTS.PERIOD_${days}`),
  }))
);
const scopeOptions = computed(() => [
  { value: 'mine', label: t('BOOKING.RESULTS.SCOPE_MINE') },
  { value: 'team', label: t('BOOKING.RESULTS.SCOPE_TEAM') },
]);
const title = computed(() =>
  scope.value === 'mine'
    ? t('BOOKING.RESULTS.TITLE_MINE')
    : t('BOOKING.RESULTS.TITLE_TEAM')
);
const isEmpty = computed(() => isEmptyTotals(stats.value?.totals));

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await BookingStatsAPI.show({
      period: period.value,
      scope: scope.value || undefined,
    });
    stats.value = data;
    scope.value = data.scope;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const changePeriod = days => {
  if (days === period.value) return;
  period.value = days;
  load();
};

const changeScope = value => {
  if (value === scope.value) return;
  scope.value = value;
  load();
};

const emptyAction = () => {
  if (period.value < 30) {
    changePeriod(30);
    return;
  }
  load();
};

load();
</script>

<template>
  <div class="flex flex-col w-full max-w-3xl gap-6 mx-auto">
    <BookingBackToCalendar v-if="entry === 'settings'" />

    <header class="flex flex-col gap-2">
      <h1 class="m-0 text-3xl font-semibold text-n-slate-12">{{ title }}</h1>
      <p class="m-0 text-lg text-n-slate-11">
        {{ t('BOOKING.RESULTS.SUBTITLE') }}
      </p>
    </header>

    <BookingSettingsTabs v-if="entry === 'settings'" />

    <div class="flex flex-wrap items-center gap-3">
      <ResultsToggle
        :model-value="period"
        :options="periodOptions"
        :label="t('BOOKING.RESULTS.PERIOD_LABEL')"
        :disabled="loading"
        @update:model-value="changePeriod"
      />
      <ResultsToggle
        v-if="stats?.can_see_team && scope"
        :model-value="scope"
        :options="scopeOptions"
        :label="t('BOOKING.RESULTS.SCOPE_LABEL')"
        :disabled="loading"
        @update:model-value="changeScope"
      />
    </div>

    <div
      v-if="loading && !stats"
      aria-busy="true"
      data-loading
      class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3"
    >
      <span class="sr-only">{{ t('BOOKING.RESULTS.LOADING') }}</span>
      <div
        v-for="item in 5"
        :key="item"
        class="h-28 rounded-2xl bg-n-alpha-2 animate-pulse"
      />
    </div>

    <div
      v-else-if="failed"
      role="alert"
      data-error
      class="flex flex-col items-start gap-4 p-6 rounded-2xl bg-n-ruby-2 ring-1 ring-inset ring-n-ruby-6"
    >
      <p class="m-0 text-base text-n-ruby-12">
        {{ t('BOOKING.RESULTS.ERROR') }}
      </p>
      <button
        type="button"
        class="inline-flex items-center min-h-11 px-5 rounded-xl text-base font-semibold text-white bg-n-ruby-9 hover:bg-n-ruby-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="load"
      >
        {{ t('BOOKING.RESULTS.RETRY') }}
      </button>
    </div>

    <template v-else-if="stats">
      <div
        v-if="isEmpty"
        data-empty
        class="flex flex-col items-center gap-4 px-6 py-10 text-center rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
      >
        <p class="m-0 text-lg font-medium text-n-slate-12">
          {{ t('BOOKING.RESULTS.EMPTY', { days: period }) }}
        </p>
        <button
          type="button"
          data-empty-action
          class="inline-flex items-center min-h-12 px-6 rounded-xl text-base font-semibold text-white bg-n-blue-9 hover:bg-n-blue-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emptyAction"
        >
          {{
            period < 30
              ? t('BOOKING.RESULTS.SEE_30')
              : t('BOOKING.RESULTS.REFRESH')
          }}
        </button>
      </div>
      <template v-else>
        <ResultsNumbers :totals="stats.totals" :days="period" />
        <ResultsOrigins :origins="stats.origins" />
      </template>
      <OpenedNotBookedList
        v-if="!isEmpty"
        :period="period"
        :scope="scope"
        @change-period="changePeriod"
      />
    </template>
  </div>
</template>
