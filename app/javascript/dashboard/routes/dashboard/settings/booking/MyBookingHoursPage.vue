<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import MyBookingHoursAPI from 'dashboard/api/crmMyBookingHours';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BookingToggle from './components/BookingToggle.vue';
import { WEEKDAYS } from './constants';
import {
  formatHour,
  formatWeekdays,
  weekdayLong,
  weekdayShort,
} from './bookingFormat';

// Meus horários (#1195, J8-A11): cada pessoa que atende escolhe os próprios
// dias e horas, sempre dentro do que as páginas permitem, e pode pausar a
// própria agenda sem pedir ao admin. Só mexe no que é da própria pessoa.
const { t } = useI18n();

const state = ref('loading'); // loading | ready | denied | error
const data = ref(null);
const form = ref({ weekdays: [], startHour: 9, endHour: 17 });
const saving = ref(false);
const problem = ref('');

const limits = computed(() => data.value?.limits || null);

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

// O horário salvo pode ter ficado fora do limite (o admin mudou a página
// depois): o formulário começa só com o que ainda cabe, para salvar não voltar
// com erro de algo que a pessoa nem vê na tela.
const fill = payload => {
  data.value = payload;
  const bounds = payload.limits;
  const days = payload.weekdays || [];
  const startHour = payload.start_hour ?? 9;
  const endHour = payload.end_hour ?? 17;
  form.value = bounds
    ? {
        weekdays: days.filter(day => bounds.weekdays.includes(day)),
        startHour: clamp(startHour, bounds.start_hour, bounds.end_hour - 1),
        endHour: clamp(endHour, bounds.start_hour + 1, bounds.end_hour),
      }
    : { weekdays: [...days], startHour, endHour };
};

const load = async () => {
  state.value = 'loading';
  try {
    const response = await MyBookingHoursAPI.show();
    fill(response.data.payload);
    state.value = 'ready';
  } catch (error) {
    state.value = error?.response?.status === 401 ? 'denied' : 'error';
  }
};

const range = (from, to) =>
  Array.from({ length: to - from + 1 }, (_, index) => from + index);

const allowedDays = computed(() =>
  WEEKDAYS.filter(day => limits.value?.weekdays.includes(day))
);
const startOptions = computed(() =>
  range(limits.value.start_hour, limits.value.end_hour - 1).map(hour => ({
    value: hour,
    label: formatHour(t, hour),
  }))
);
const endOptions = computed(() =>
  range(limits.value.start_hour + 1, limits.value.end_hour).map(hour => ({
    value: hour,
    label: formatHour(t, hour),
  }))
);
const limitText = computed(() =>
  t('BOOKING.MY_HOURS.LIMIT', {
    days: formatWeekdays(t, limits.value.weekdays),
    from: formatHour(t, limits.value.start_hour),
    to: formatHour(t, limits.value.end_hour),
  })
);

const toggleDay = day => {
  const days = form.value.weekdays;
  form.value = {
    ...form.value,
    weekdays: days.includes(day)
      ? days.filter(item => item !== day)
      : [...days, day],
  };
};

const formProblem = computed(() => {
  if (!form.value.weekdays.length) return 'DAYS';
  if (form.value.startHour >= form.value.endHour) return 'HOURS';
  return '';
});

const SERVER_PROBLEMS = {
  'crm.booking_v2.my_hours_outside_page': 'OUTSIDE',
  'crm.booking_v2.my_hours_invalid': 'HOURS',
  'crm.booking_v2.my_hours_no_pages': 'NO_PAGES',
};

const send = async (request, okMessage) => {
  saving.value = true;
  problem.value = '';
  try {
    const response = await request();
    fill(response.data.payload);
    useAlert(okMessage);
  } catch (error) {
    const key = SERVER_PROBLEMS[error?.response?.data?.error] || 'GENERIC';
    problem.value = t(`BOOKING.MY_HOURS.ERRORS.${key}`);
  } finally {
    saving.value = false;
  }
};

const save = () => {
  if (formProblem.value) {
    problem.value = t(`BOOKING.MY_HOURS.ERRORS.${formProblem.value}`);
    return;
  }
  send(
    () =>
      MyBookingHoursAPI.save({
        weekdays: [...form.value.weekdays].sort((a, b) => a - b),
        startHour: form.value.startHour,
        endHour: form.value.endHour,
      }),
    t('BOOKING.MY_HOURS.SAVED')
  );
};

const usePageHours = () =>
  send(() => MyBookingHoursAPI.usePageHours(), t('BOOKING.MY_HOURS.SAVED'));

const togglePause = () => {
  const paused = !data.value.paused;
  send(
    () => MyBookingHoursAPI.setPaused(paused),
    paused ? t('BOOKING.MY_HOURS.PAUSED_OK') : t('BOOKING.MY_HOURS.RESUMED_OK')
  );
};

onMounted(load);

const PRIMARY =
  'inline-flex items-center gap-2 min-h-11 px-5 rounded-xl text-base font-semibold text-white bg-n-blue-9 hover:bg-n-blue-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60 disabled:cursor-not-allowed';
const SECONDARY =
  'inline-flex items-center gap-2 min-h-11 px-5 rounded-xl text-base font-medium text-n-slate-12 bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:ring-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60 disabled:cursor-not-allowed';
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-surface-1">
    <div class="flex flex-col w-full max-w-3xl gap-8 px-6 py-8 mx-auto">
      <header class="flex flex-col gap-2">
        <h1 class="m-0 text-3xl font-semibold text-n-slate-12">
          {{ t('BOOKING.MY_HOURS.TITLE') }}
        </h1>
        <p class="m-0 text-lg text-n-slate-11">
          {{ t('BOOKING.MY_HOURS.SUBTITLE') }}
        </p>
      </header>

      <p
        v-if="state === 'loading'"
        data-loading
        aria-busy="true"
        class="m-0 text-base text-n-slate-11"
      >
        {{ t('BOOKING.LIST.LOADING') }}
      </p>

      <p
        v-else-if="state === 'denied'"
        data-denied
        role="status"
        class="m-0 text-base text-n-slate-12"
      >
        {{ t('BOOKING.MY_HOURS.DENIED') }}
      </p>

      <div
        v-else-if="state === 'error'"
        data-error
        role="alert"
        class="flex flex-col items-start gap-4"
      >
        <p class="m-0 text-base text-n-ruby-11">
          {{ t('BOOKING.LIST.ERROR') }}
        </p>
        <button type="button" :class="SECONDARY" @click="load">
          {{ t('BOOKING.LIST.RETRY') }}
        </button>
      </div>

      <template v-else>
        <section
          data-pause-card
          class="flex flex-wrap items-center justify-between gap-4 p-6 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
        >
          <div class="flex flex-col gap-1 min-w-0">
            <h2 class="m-0 text-lg font-semibold text-n-slate-12">
              {{
                data.paused
                  ? t('BOOKING.MY_HOURS.PAUSED_TITLE')
                  : t('BOOKING.MY_HOURS.PAUSE_TITLE')
              }}
            </h2>
            <p class="m-0 text-base text-n-slate-11">
              {{
                data.paused
                  ? t('BOOKING.MY_HOURS.PAUSED_HINT')
                  : t('BOOKING.MY_HOURS.PAUSE_HINT')
              }}
            </p>
          </div>
          <button
            type="button"
            data-pause
            :aria-pressed="data.paused ? 'true' : 'false'"
            :disabled="saving"
            :class="data.paused ? PRIMARY : SECONDARY"
            @click="togglePause"
          >
            <span
              :class="data.paused ? 'i-lucide-play' : 'i-lucide-pause'"
              class="size-4"
              aria-hidden="true"
            />
            {{
              data.paused
                ? t('BOOKING.MY_HOURS.RESUME')
                : t('BOOKING.MY_HOURS.PAUSE')
            }}
          </button>
        </section>

        <p
          v-if="!limits"
          data-no-pages
          class="m-0 p-6 text-base rounded-2xl bg-n-alpha-1 text-n-slate-12"
        >
          {{ t('BOOKING.MY_HOURS.NO_PAGES') }}
        </p>

        <section
          v-else
          data-hours
          class="flex flex-col gap-6 p-6 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
        >
          <p data-limit class="m-0 text-base text-n-slate-11">
            {{ limitText }}
          </p>

          <fieldset class="flex flex-col gap-3 p-0 m-0 border-0">
            <legend class="p-0 mb-1 text-base font-semibold text-n-slate-12">
              {{ t('BOOKING.WHEN.DAYS_LABEL') }}
            </legend>
            <div data-weekdays class="flex flex-wrap gap-2">
              <BookingToggle
                v-for="day in allowedDays"
                :key="day"
                :data-day="day"
                :label="weekdayShort(t, day)"
                :aria-label="weekdayLong(t, day)"
                :pressed="form.weekdays.includes(day)"
                @toggle="toggleDay(day)"
              />
            </div>
          </fieldset>

          <div class="grid gap-4 sm:grid-cols-2">
            <div class="flex flex-col gap-2">
              <p class="m-0 text-base font-semibold text-n-slate-12">
                {{ t('BOOKING.WHEN.FROM') }}
              </p>
              <ChoiceSelect
                data-start
                :model-value="form.startHour"
                :options="startOptions"
                :aria-label="t('BOOKING.WHEN.FROM')"
                @update:model-value="form = { ...form, startHour: $event }"
              />
            </div>
            <div class="flex flex-col gap-2">
              <p class="m-0 text-base font-semibold text-n-slate-12">
                {{ t('BOOKING.WHEN.TO') }}
              </p>
              <ChoiceSelect
                data-end
                :model-value="form.endHour"
                :options="endOptions"
                :aria-label="t('BOOKING.WHEN.TO')"
                @update:model-value="form = { ...form, endHour: $event }"
              />
            </div>
          </div>

          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              data-save
              :disabled="saving"
              :class="PRIMARY"
              @click="save"
            >
              {{ t('BOOKING.MY_HOURS.SAVE') }}
            </button>
            <button
              v-if="data.custom_hours"
              type="button"
              data-use-page
              :disabled="saving"
              :class="SECONDARY"
              @click="usePageHours"
            >
              {{ t('BOOKING.MY_HOURS.USE_PAGE') }}
            </button>
          </div>
        </section>

        <p
          v-if="problem"
          data-problem
          role="alert"
          class="m-0 text-base text-n-ruby-11"
        >
          {{ problem }}
        </p>
      </template>
    </div>
  </div>
</template>
