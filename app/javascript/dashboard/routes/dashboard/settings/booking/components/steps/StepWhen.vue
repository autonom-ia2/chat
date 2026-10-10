<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BookingToggle from '../BookingToggle.vue';
import {
  BUFFER_OPTIONS,
  EXTRA_DURATION_OPTIONS,
  MAX_EXTRA_DURATIONS,
  NOTICE_OPTIONS,
  WEEKDAYS,
} from '../../constants';
import {
  formatHour,
  formatMinutes,
  weekdayLong,
  weekdayShort,
} from '../../bookingFormat';

// Passo 4: dias, horário, antecedência mínima, intervalo, feriados nacionais
// (ligado por padrão, #1195) e durações extras.
// Tudo com opções prontas; nenhum número digitado.
const props = defineProps({
  form: { type: Object, required: true },
  error: { type: String, default: '' },
});

const emit = defineEmits(['change']);
const { t } = useI18n();

const range = (from, to) =>
  Array.from({ length: to - from + 1 }, (_, index) => from + index);

const startOptions = computed(() =>
  range(0, 23).map(hour => ({ value: hour, label: formatHour(t, hour) }))
);
const endOptions = computed(() =>
  range(1, 24).map(hour => ({ value: hour, label: formatHour(t, hour) }))
);

// O valor salvo entra na lista mesmo quando não é uma das opções prontas.
const withCurrent = (values, current) =>
  values.includes(current)
    ? values
    : [...values, current].sort((a, b) => a - b);

const noticeOptions = computed(() =>
  withCurrent(NOTICE_OPTIONS, props.form.minNoticeMinutes).map(value => ({
    value,
    label: value
      ? t('BOOKING.WHEN.NOTICE_VALUE', { value: formatMinutes(t, value) })
      : t('BOOKING.WHEN.NOTICE_NONE'),
  }))
);
const bufferOptions = computed(() =>
  withCurrent(BUFFER_OPTIONS, props.form.bufferMinutes).map(value => ({
    value,
    label: value
      ? t('BOOKING.WHEN.BUFFER_VALUE', { value: formatMinutes(t, value) })
      : t('BOOKING.WHEN.BUFFER_NONE'),
  }))
);
const extraOptions = computed(() =>
  EXTRA_DURATION_OPTIONS.filter(value => value !== props.form.durationMinutes)
);

const toggleDay = day => {
  const days = props.form.weekdays;
  emit('change', {
    weekdays: days.includes(day)
      ? days.filter(item => item !== day)
      : [...days, day],
  });
};

const extraChosen = value => props.form.slotDurations.includes(value);
const extraFull = computed(
  () => props.form.slotDurations.length >= MAX_EXTRA_DURATIONS
);
const toggleExtra = value => {
  const list = props.form.slotDurations;
  emit('change', {
    slotDurations: extraChosen(value)
      ? list.filter(item => item !== value)
      : [...list, value].sort((a, b) => a - b),
  });
};
</script>

<template>
  <section class="flex flex-col gap-6">
    <h2
      tabindex="-1"
      class="m-0 text-2xl font-semibold text-n-slate-12 focus:outline-none"
    >
      {{ t('BOOKING.WHEN.TITLE') }}
    </h2>

    <fieldset class="flex flex-col gap-3 p-0 m-0 border-0">
      <legend class="p-0 mb-1 text-base font-semibold text-n-slate-12">
        {{ t('BOOKING.WHEN.DAYS_LABEL') }}
      </legend>
      <div
        data-weekdays
        :data-invalid="error === 'WEEKDAYS' || undefined"
        class="flex flex-wrap gap-2"
      >
        <BookingToggle
          v-for="day in WEEKDAYS"
          :key="day"
          :data-day="day"
          :label="weekdayShort(t, day)"
          :aria-label="weekdayLong(t, day)"
          :pressed="form.weekdays.includes(day)"
          @toggle="toggleDay(day)"
        />
      </div>
      <p
        v-if="error === 'WEEKDAYS'"
        role="alert"
        class="m-0 text-base text-n-ruby-11"
      >
        {{ t('BOOKING.WIZARD.ERRORS.WEEKDAYS') }}
      </p>
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
          @update:model-value="emit('change', { startHour: $event })"
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
          :invalid="error === 'HOURS'"
          @update:model-value="emit('change', { endHour: $event })"
        />
      </div>
    </div>
    <p
      v-if="error === 'HOURS'"
      role="alert"
      class="m-0 text-base text-n-ruby-11"
    >
      {{ t('BOOKING.WIZARD.ERRORS.HOURS') }}
    </p>

    <div class="grid gap-4 sm:grid-cols-2">
      <div class="flex flex-col gap-2">
        <p class="m-0 text-base font-semibold text-n-slate-12">
          {{ t('BOOKING.WHEN.NOTICE_LABEL') }}
        </p>
        <ChoiceSelect
          data-notice
          :model-value="form.minNoticeMinutes"
          :options="noticeOptions"
          :aria-label="t('BOOKING.WHEN.NOTICE_LABEL')"
          @update:model-value="emit('change', { minNoticeMinutes: $event })"
        />
      </div>
      <div class="flex flex-col gap-2">
        <p class="m-0 text-base font-semibold text-n-slate-12">
          {{ t('BOOKING.WHEN.BUFFER_LABEL') }}
        </p>
        <ChoiceSelect
          data-buffer
          :model-value="form.bufferMinutes"
          :options="bufferOptions"
          :aria-label="t('BOOKING.WHEN.BUFFER_LABEL')"
          @update:model-value="emit('change', { bufferMinutes: $event })"
        />
      </div>
    </div>

    <div class="flex flex-col gap-2">
      <p class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('BOOKING.WHEN.HOLIDAYS_LABEL') }}
      </p>
      <div class="flex">
        <BookingToggle
          data-holidays
          :label="t('BOOKING.WHEN.HOLIDAYS_TOGGLE')"
          :pressed="form.closeHolidays"
          @toggle="emit('change', { closeHolidays: !form.closeHolidays })"
        />
      </div>
      <p class="m-0 text-base text-n-slate-11">
        {{
          form.closeHolidays
            ? t('BOOKING.WHEN.HOLIDAYS_ON_HINT')
            : t('BOOKING.WHEN.HOLIDAYS_OFF_HINT')
        }}
      </p>
    </div>

    <fieldset class="flex flex-col gap-3 p-0 m-0 border-0">
      <legend class="p-0 mb-1 text-base font-semibold text-n-slate-12">
        {{ t('BOOKING.WHEN.EXTRA_LABEL') }}
      </legend>
      <p class="m-0 text-base text-n-slate-11">
        {{ t('BOOKING.WHEN.EXTRA_HINT') }}
      </p>
      <div data-extras class="flex flex-wrap gap-2">
        <BookingToggle
          v-for="value in extraOptions"
          :key="value"
          :data-extra="value"
          :label="formatMinutes(t, value)"
          :pressed="extraChosen(value)"
          :disabled="extraFull && !extraChosen(value)"
          @toggle="toggleExtra(value)"
        />
      </div>
    </fieldset>
  </section>
</template>
