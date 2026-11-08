<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { intlLocale } from '../metaAdsHelpers';

// Anúncios da Meta (#2198): escolher um dia, com a cara do painel (o `type="date"` do navegador muda de navegador
// para navegador e mostra "dd/mm/aaaa"). O botão mostra a data por extenso; tocar abre o mês logo abaixo, no fluxo
// da página (dentro de janela não corta). Teclado do padrão WAI-ARIA de grade de datas: setas andam um dia ou uma
// semana, Enter/Espaço escolhe, Esc fecha. Dias antes de `min` ficam desabilitados.
// Valor: 'AAAA-MM-DD' (dia do calendário, sem fuso) ou ''.
const props = defineProps({
  label: { type: String, required: true },
  min: { type: String, default: '' },
  placeholder: { type: String, default: '' },
});

const model = defineModel({ type: String, default: '' });

const { t, locale } = useI18n();

const open = ref(false);
const grid = ref(null);
const trigger = ref(null);
const uid = Math.random().toString(36).slice(2, 8);

const toDate = iso => new Date(`${iso}T12:00:00`);
const toIso = date => {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
};
const todayIso = () => toIso(new Date());

const shown = ref(toDate(model.value || props.min || todayIso()));
const focused = ref(model.value || props.min || todayIso());

const fmtLong = iso =>
  toDate(iso).toLocaleDateString(intlLocale(locale.value), {
    weekday: 'short',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });

// "outubro de 2026" → "Outubro de 2026": só a primeira letra (o `capitalize` do CSS faria "Outubro De 2026").
const monthTitle = computed(() => {
  const title = shown.value.toLocaleDateString(intlLocale(locale.value), {
    month: 'long',
    year: 'numeric',
  });
  return title.charAt(0).toUpperCase() + title.slice(1);
});

// Domingo primeiro, como o calendário de parede brasileiro.
const weekdays = computed(() =>
  Array.from({ length: 7 }, (_, index) =>
    new Date(2026, 1, 1 + index).toLocaleDateString(intlLocale(locale.value), {
      weekday: 'narrow',
    })
  )
);

const weeks = computed(() => {
  const first = new Date(
    shown.value.getFullYear(),
    shown.value.getMonth(),
    1,
    12
  );
  const start = new Date(first);
  start.setDate(1 - first.getDay());
  return Array.from({ length: 6 }, (_, week) =>
    Array.from({ length: 7 }, (__, day) => {
      const date = new Date(start);
      date.setDate(start.getDate() + week * 7 + day);
      const iso = toIso(date);
      return {
        iso,
        day: date.getDate(),
        outside: date.getMonth() !== shown.value.getMonth(),
        disabled: Boolean(props.min) && iso < props.min,
        label: fmtLong(iso),
      };
    })
  );
});

const focusDay = () =>
  nextTick(() =>
    grid.value?.querySelector(`[data-day="${focused.value}"]`)?.focus()
  );

const toggle = () => {
  open.value = !open.value;
  if (!open.value) return;
  focused.value = model.value || props.min || todayIso();
  shown.value = toDate(focused.value);
  focusDay();
};

const close = () => {
  open.value = false;
  nextTick(() => trigger.value?.focus());
};

const choose = cell => {
  if (cell.disabled) return;
  model.value = cell.iso;
  close();
};

const moveMonth = step => {
  const next = new Date(shown.value);
  next.setDate(1);
  next.setMonth(next.getMonth() + step);
  shown.value = next;
};

// Setas: um dia ou uma semana. Home/End: começo e fim da semana. PageUp/PageDown: um mês (com Shift, um ano).
const DAY_STEPS = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 };
const shiftMonths = (date, months) => {
  const next = new Date(date);
  const day = next.getDate();
  next.setDate(1);
  next.setMonth(next.getMonth() + months);
  const last = new Date(next.getFullYear(), next.getMonth() + 1, 0).getDate();
  next.setDate(Math.min(day, last));
  return next;
};

const targetOf = (event, date) => {
  const next = new Date(date);
  if (DAY_STEPS[event.key]) {
    next.setDate(next.getDate() + DAY_STEPS[event.key]);
    return next;
  }
  if (event.key === 'Home') {
    next.setDate(next.getDate() - next.getDay());
    return next;
  }
  if (event.key === 'End') {
    next.setDate(next.getDate() + (6 - next.getDay()));
    return next;
  }
  const months = event.shiftKey ? 12 : 1;
  if (event.key === 'PageUp') return shiftMonths(next, -months);
  if (event.key === 'PageDown') return shiftMonths(next, months);
  return null;
};

// Dia antes de `min` não recebe foco: andando para trás, para no primeiro dia permitido.
const allowed = date =>
  !props.min || toIso(date) >= props.min ? date : toDate(props.min);

const onKey = (event, cell) => {
  if (event.key === 'Escape') {
    event.preventDefault();
    close();
    return;
  }
  if (event.key === 'Enter' || event.key === ' ') {
    event.preventDefault();
    choose(cell);
    return;
  }
  const target = targetOf(event, toDate(cell.iso));
  if (!target) return;
  event.preventDefault();
  const next = allowed(target);
  focused.value = toIso(next);
  if (
    next.getMonth() !== shown.value.getMonth() ||
    next.getFullYear() !== shown.value.getFullYear()
  ) {
    shown.value = next;
  }
  focusDay();
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <span :id="`data-${uid}`" class="text-sm font-medium text-n-slate-12">
      {{ label }}
    </span>
    <button
      ref="trigger"
      type="button"
      data-campo-data
      :aria-labelledby="`data-${uid} data-${uid}-valor`"
      :aria-expanded="open"
      class="flex h-11 w-full items-center justify-between gap-3 rounded-lg border-0 bg-n-alpha-black2 px-3 text-start text-sm text-n-slate-12 outline outline-1 outline-n-weak hover:outline-n-strong focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="toggle"
    >
      <span
        :id="`data-${uid}-valor`"
        :class="model ? 'text-n-slate-12' : 'text-n-slate-10'"
      >
        {{ model ? fmtLong(model) : placeholder }}
      </span>
      <span
        class="i-lucide-calendar size-4 text-n-slate-11"
        aria-hidden="true"
      />
    </button>
    <div
      v-if="open"
      ref="grid"
      data-campo-data-mes
      role="group"
      :aria-label="label"
      class="flex flex-col gap-3 rounded-xl bg-n-solid-1 p-3 shadow-lg ring-1 ring-n-weak"
    >
      <div class="flex items-center justify-between gap-2">
        <button
          type="button"
          class="grid size-11 place-items-center rounded-lg border-0 bg-transparent text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :aria-label="t('CRM_KANBAN.META_ADS_HUB.CRIAR.DATE.PREVIOUS')"
          @click="moveMonth(-1)"
        >
          <span class="i-lucide-chevron-left size-4" aria-hidden="true" />
        </button>
        <span class="text-sm font-semibold text-n-slate-12" aria-live="polite">
          {{ monthTitle }}
        </span>
        <button
          type="button"
          class="grid size-11 place-items-center rounded-lg border-0 bg-transparent text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :aria-label="t('CRM_KANBAN.META_ADS_HUB.CRIAR.DATE.NEXT')"
          @click="moveMonth(1)"
        >
          <span class="i-lucide-chevron-right size-4" aria-hidden="true" />
        </button>
      </div>
      <table role="grid" class="w-full border-collapse text-center">
        <thead>
          <tr>
            <th
              v-for="(name, index) in weekdays"
              :key="index"
              scope="col"
              class="pb-1 text-xs font-medium uppercase text-n-slate-10"
            >
              {{ name }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(week, index) in weeks" :key="index">
            <td
              v-for="cell in week"
              :key="cell.iso"
              role="gridcell"
              :aria-selected="cell.iso === model"
              class="p-0.5"
            >
              <button
                type="button"
                :data-day="cell.iso"
                :tabindex="cell.iso === focused ? 0 : -1"
                :aria-label="cell.label"
                :aria-disabled="cell.disabled"
                class="grid size-11 w-full place-items-center rounded-lg border-0 text-sm tabular-nums focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                :class="[
                  cell.iso === model
                    ? 'bg-n-brand font-semibold text-white'
                    : 'bg-transparent hover:bg-n-alpha-2',
                  cell.outside && cell.iso !== model ? 'text-n-slate-9' : '',
                  !cell.outside && cell.iso !== model ? 'text-n-slate-12' : '',
                  cell.disabled ? 'cursor-not-allowed opacity-40' : '',
                ]"
                @click="choose(cell)"
                @keydown="onKey($event, cell)"
              >
                {{ cell.day }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
