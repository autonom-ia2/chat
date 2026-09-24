<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBreakpoints, breakpointsTailwind } from '@vueuse/core';
import {
  addMonths,
  addWeeks,
  addDays,
  startOfMonth,
  startOfWeek,
  startOfDay,
} from 'date-fns';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmCalendarHeader from './CrmCalendarHeader.vue';
import CrmCalendarMonthGrid from './CrmCalendarMonthGrid.vue';
import CrmCalendarWeekGrid from './CrmCalendarWeekGrid.vue';
import CrmCalendarDayGrid from './CrmCalendarDayGrid.vue';
import CrmCalendarAgenda from './CrmCalendarAgenda.vue';
import {
  monthRange,
  weekRange,
  dayRange,
  filterByOverlays,
  filterByOwner,
  overdueCount,
} from './calendarEvents.js';

const props = defineProps({
  events: {
    type: Array,
    default: () => [],
  },
  loading: {
    type: Boolean,
    default: false,
  },
  error: {
    type: Boolean,
    default: false,
  },
  // Roster of agents — kept on the public contract for owner-aware sub-views
  // and quick-add owner pickers (owned by sibling components).
  // eslint-disable-next-line vue/no-unused-properties
  owners: {
    type: Array,
    default: () => [],
  },
  currentUserId: {
    type: [Number, String],
    default: null,
  },
  timezone: {
    type: String,
    default: '',
  },
  // Funil ativo — usado pelo atalho do toggle "Lembrete de retorno por IA" no header.
  pipelineId: {
    type: [String, Number],
    default: null,
  },
  // Suspende os atalhos de teclado enquanto um drawer/modal está aberto sobre o
  // calendário (evita navegar o mês ou abrir "novo" por trás do drawer).
  paused: {
    type: Boolean,
    default: false,
  },
  // Funis disponíveis ({ value, label }) — o seletor mora no header do calendário
  // (a faixa de filtros/funil do board fica oculta no modo Calendário).
  pipelines: {
    type: Array,
    default: () => [],
  },
});

// Emit names are camelCase (Vue convention); parents listen via kebab-case
// (@range-change → rangeChange) as named in the implementation manifest.
const emit = defineEmits([
  'rangeChange',
  'viewChange',
  'openEvent',
  'quickAdd',
  'reschedule',
  'retry',
  'update:pipelineId',
]);

const { t } = useI18n();

/* -------------------------------------------------------------------------- */
/* Owned UI state                                                             */
/* -------------------------------------------------------------------------- */
const view = ref('month');
const cursorDate = ref(new Date());
const overlays = ref({
  reminders: true,
  whatsapp: true,
  closeDates: true,
  meetings: true,
  external: true,
});
const ownerScope = ref('all');
// "Histórico": completed/canceled follow-ups are hidden by default (they crowd
// the grid); toggling this refetches with include_completed=true.
const showCompleted = ref(false);

/* Below md, force agenda (the mobile-friendly view) regardless of selection. */
const breakpoints = useBreakpoints(breakpointsTailwind);
const belowMd = breakpoints.smaller('md');

const effectiveView = computed(() => (belowMd.value ? 'agenda' : view.value));

/* -------------------------------------------------------------------------- */
/* Visible date range — derived from view + cursor; drives the parent fetch   */
/* -------------------------------------------------------------------------- */
const visibleRange = computed(() => {
  switch (effectiveView.value) {
    case 'week':
      return weekRange(cursorDate.value);
    case 'day':
      return dayRange(cursorDate.value);
    case 'agenda':
    case 'month':
    default:
      return monthRange(cursorDate.value);
  }
});

const emitRangeChange = () => {
  const { from, to } = visibleRange.value;
  emit('rangeChange', {
    from: from.toISOString(),
    to: to.toISOString(),
    includeCompleted: showCompleted.value,
  });
};

// Emit on mount and whenever the visible window OR the history toggle changes
// (both drive the parent refetch).
watch([visibleRange, showCompleted], () => emitRangeChange(), {
  immediate: true,
  deep: false,
});

/* -------------------------------------------------------------------------- */
/* Event pipeline: overlay toggles + owner scope (client-side)                */
/* -------------------------------------------------------------------------- */
const visibleEvents = computed(() => {
  const byOverlay = filterByOverlays(props.events, overlays.value);
  return filterByOwner(byOverlay, ownerScope.value, props.currentUserId);
});

const overdue = computed(() => overdueCount(visibleEvents.value));

const isEmpty = computed(
  () => !props.loading && !props.error && visibleEvents.value.length === 0
);

/* -------------------------------------------------------------------------- */
/* Header actions                                                             */
/* -------------------------------------------------------------------------- */
const goToday = () => {
  cursorDate.value = new Date();
};

const goPrev = () => {
  switch (effectiveView.value) {
    case 'week':
      cursorDate.value = addWeeks(cursorDate.value, -1);
      break;
    case 'day':
      cursorDate.value = addDays(cursorDate.value, -1);
      break;
    default:
      cursorDate.value = addMonths(cursorDate.value, -1);
  }
};

const goNext = () => {
  switch (effectiveView.value) {
    case 'week':
      cursorDate.value = addWeeks(cursorDate.value, 1);
      break;
    case 'day':
      cursorDate.value = addDays(cursorDate.value, 1);
      break;
    default:
      cursorDate.value = addMonths(cursorDate.value, 1);
  }
};

const onUpdateView = next => {
  view.value = next;
  emit('viewChange', next);
};

const onUpdateCursor = next => {
  if (next) cursorDate.value = next;
};

const onUpdateOverlays = next => {
  overlays.value = next;
};

const onUpdateOwnerScope = next => {
  ownerScope.value = next;
};

const onUpdateShowCompleted = next => {
  showCompleted.value = next === true;
};

/* -------------------------------------------------------------------------- */
/* Grid actions                                                               */
/* -------------------------------------------------------------------------- */
const onEventClick = event => emit('openEvent', event);

// Month-day click drills into that day.
const onDayClick = date => {
  cursorDate.value = startOfDay(date);
  if (!belowMd.value) view.value = 'day';
};

// Empty slot click → quick-add prefilled.
const onSlotClick = payload => {
  const date = payload?.date || payload;
  emit('quickAdd', { date, type: 'reminder' });
};

const onQuickAddNew = () => {
  emit('quickAdd', { date: cursorDate.value, type: 'reminder' });
};

// Drag-to-reschedule from month grid → { event, date }.
const onEventDropMonth = ({ event, date }) =>
  emit('reschedule', { event, date });

// Drag-to-reschedule from week/day time-grid → { event, startsAt }.
const onEventDropTime = ({ event, startsAt }) =>
  emit('reschedule', { event, date: startsAt });

/* Keep cursor normalized to the start of its period for stable ranges. */
watch(view, next => {
  if (next === 'month') cursorDate.value = startOfMonth(cursorDate.value);
  if (next === 'week')
    cursorDate.value = startOfWeek(cursorDate.value, { weekStartsOn: 0 });
});

/* -------------------------------------------------------------------------- */
/* Keyboard shortcuts — the industry-canonical map (Google Calendar):         */
/* T today · C new · ←/→ prev/next period. Ignored while typing in a field.   */
/* -------------------------------------------------------------------------- */
const isTypingTarget = el =>
  !!el &&
  (el.tagName === 'INPUT' ||
    el.tagName === 'TEXTAREA' ||
    el.tagName === 'SELECT' ||
    el.isContentEditable ||
    // O ChoiceSelect busca opção por letra e navega por seta, como o <select>
    // nativo: gatilho e lista não disparam os atalhos do calendário.
    !!el.closest?.('[role="combobox"], [role="listbox"]'));

const onKeydown = e => {
  if (props.paused) return;
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (isTypingTarget(e.target)) return;
  switch (e.key) {
    case 't':
    case 'T':
      goToday();
      break;
    case 'c':
    case 'C':
      onQuickAddNew();
      break;
    case 'ArrowLeft':
      goPrev();
      break;
    case 'ArrowRight':
      goNext();
      break;
    default:
      return;
  }
  e.preventDefault();
};

onMounted(() => window.addEventListener('keydown', onKeydown));
onBeforeUnmount(() => window.removeEventListener('keydown', onKeydown));
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-2">
    <CrmCalendarHeader
      :view="effectiveView"
      :cursor-date="cursorDate"
      :overlays="overlays"
      :owner-scope="ownerScope"
      :show-completed="showCompleted"
      :overdue-count="overdue"
      :pipeline-id="pipelineId"
      :pipelines="pipelines"
      @update:pipeline-id="emit('update:pipelineId', $event)"
      @prev="goPrev"
      @next="goNext"
      @today="goToday"
      @update:view="onUpdateView"
      @update:cursor-date="onUpdateCursor"
      @update:overlays="onUpdateOverlays"
      @update:owner-scope="onUpdateOwnerScope"
      @update:show-completed="onUpdateShowCompleted"
      @quick-add="onQuickAddNew"
    />

    <p v-if="timezone" class="text-xs text-n-slate-10">
      {{ t('CRM_KANBAN.CALENDAR.TIMEZONE', { tz: timezone }) }}
    </p>

    <!-- Loading -->
    <div
      v-if="loading"
      class="flex min-h-0 flex-1 items-center justify-center rounded-lg border border-n-weak bg-n-surface-1 py-16"
    >
      <Spinner />
    </div>

    <!-- Error -->
    <div
      v-else-if="error"
      class="flex min-h-0 flex-1 flex-col items-center justify-center gap-3 rounded-lg border border-dashed border-n-weak px-6 py-16 text-center"
    >
      <span class="i-lucide-alert-triangle size-6 text-n-ruby-11" />
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('CRM_KANBAN.CALENDAR.RESCHEDULE_ERROR') }}
      </p>
      <Button
        variant="outline"
        color="slate"
        size="sm"
        :label="t('CRM_KANBAN.CALENDAR.RETRY')"
        @click="emit('retry')"
      />
    </div>

    <!-- Grid / Agenda -->
    <div v-else class="flex min-h-0 flex-1 flex-col">
      <CrmCalendarMonthGrid
        v-if="effectiveView === 'month'"
        :cursor-date="cursorDate"
        :events="visibleEvents"
        :overlays="overlays"
        @day-click="onDayClick"
        @event-click="onEventClick"
        @slot-click="onSlotClick"
        @event-drop="onEventDropMonth"
      />
      <CrmCalendarWeekGrid
        v-else-if="effectiveView === 'week'"
        :cursor-date="cursorDate"
        :events="visibleEvents"
        :overlays="overlays"
        :timezone="timezone"
        @event-click="onEventClick"
        @slot-click="onSlotClick"
        @event-drop="onEventDropTime"
      />
      <CrmCalendarDayGrid
        v-else-if="effectiveView === 'day'"
        :cursor-date="cursorDate"
        :events="visibleEvents"
        :overlays="overlays"
        :timezone="timezone"
        @event-click="onEventClick"
        @slot-click="onSlotClick"
        @event-drop="onEventDropTime"
      />
      <CrmCalendarAgenda
        v-else
        :events="visibleEvents"
        :overlays="overlays"
        @event-click="onEventClick"
        @quick-add="onQuickAddNew"
        @retry="emit('retry')"
      />

      <!-- Empty overlay keeps the grid visible behind a contextual hint -->
      <div
        v-if="isEmpty"
        class="mt-3 flex items-center justify-center rounded-lg border border-dashed border-n-weak px-6 py-6 text-center"
      >
        <div>
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.CALENDAR.EMPTY_TITLE') }}
          </p>
          <p class="mb-2 text-xs text-n-slate-11">
            {{ t('CRM_KANBAN.CALENDAR.EMPTY_HELP') }}
          </p>
          <Button
            variant="faded"
            color="blue"
            size="sm"
            icon="i-lucide-plus"
            :label="t('CRM_KANBAN.CALENDAR.NEW')"
            @click="onQuickAddNew"
          />
        </div>
      </div>
    </div>
  </div>
</template>
