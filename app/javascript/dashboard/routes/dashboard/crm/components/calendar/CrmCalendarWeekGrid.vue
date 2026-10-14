<script setup>
import { computed, ref, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  format,
  isToday as dateFnsIsToday,
  isSameDay,
  getHours,
  getMinutes,
  setHours,
  setMinutes,
  startOfDay,
} from 'date-fns';
import {
  weekDays,
  weekdayLabels,
  eventsForDay,
  eventStart,
  eventColorClass,
  eventIconClass,
  eventTextClass,
  isOverdue,
  isDraggable,
  isValidDrop,
  filterByOverlays,
  eventTime,
  EVENT_TYPE_GROUP,
  OVERLAY_GROUP,
  DAY_HOURS,
  ptBR,
} from './calendarEvents.js';

const props = defineProps({
  cursorDate: {
    type: Date,
    required: true,
  },
  events: {
    type: Array,
    default: () => [],
  },
  overlays: {
    type: Object,
    default: () => ({
      reminders: true,
      whatsapp: true,
      closeDates: true,
      meetings: true,
    }),
  },
  // eslint-disable-next-line vue/no-unused-properties
  timezone: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['eventClick', 'slotClick', 'eventDrop']);

const { t } = useI18n();

/* -------------------------------------------------------------------------- */
/* Layout constants                                                           */
/* -------------------------------------------------------------------------- */
const HOUR_HEIGHT = 48; // px per hour row (h-12)
const SNAP_MINUTES = 15; // drag snap granularity
const WHATSAPP_BLOCK_MINUTES = 30; // fixed visual height for zero-duration sends

const hours = DAY_HOURS;

/* -------------------------------------------------------------------------- */
/* Days (Sunday-first, pt_BR) + headers                                       */
/* -------------------------------------------------------------------------- */
const days = computed(() => weekDays(props.cursorDate));
const weekdayShort = computed(() => weekdayLabels('EEEEEE'));

const dayKey = day => format(day, 'yyyy-MM-dd');
const dayNumber = day => format(day, 'd', { locale: ptBR });
const dayAria = day => format(day, "EEEE, d 'de' MMMM", { locale: ptBR });
const isCurrentDay = day => dateFnsIsToday(day);

/* -------------------------------------------------------------------------- */
/* Event partitioning: all-day (reminders & forecasts) vs timed (whatsapp)    */
/* -------------------------------------------------------------------------- */
const shownEvents = computed(() =>
  filterByOverlays(props.events, props.overlays)
);

// WhatsApp sends and meetings are precise instants → timed blocks.
// Reminders / forecasts render in the all-day row (task-like milestones).
const isTimedEvent = event =>
  [OVERLAY_GROUP.WHATSAPP, OVERLAY_GROUP.MEETING].includes(
    EVENT_TYPE_GROUP(event.event_type)
  );

const allDayEventsForDay = day =>
  eventsForDay(shownEvents.value, day).filter(e => !isTimedEvent(e));

const timedEventsForDay = day =>
  eventsForDay(shownEvents.value, day).filter(e => isTimedEvent(e));

const hasAnyAllDay = computed(() =>
  days.value.some(day => allDayEventsForDay(day).length > 0)
);

/* -------------------------------------------------------------------------- */
/* Timed-event positioning (dynamic pixel geometry — the one place a :style   */
/* is unavoidable for a time-grid, mirroring the now-line offset below)       */
/* -------------------------------------------------------------------------- */
const topForEvent = event => {
  const start = eventStart(event);
  if (!start) return 0;
  return ((getHours(start) * 60 + getMinutes(start)) / 60) * HOUR_HEIGHT;
};

const heightForEvent = event => {
  if (EVENT_TYPE_GROUP(event.event_type) === OVERLAY_GROUP.WHATSAPP) {
    return (WHATSAPP_BLOCK_MINUTES / 60) * HOUR_HEIGHT;
  }

  const start = eventStart(event);
  const end = event?.ends_at ? new Date(event.ends_at) : null;
  const minutes =
    start && end && !Number.isNaN(end.getTime())
      ? Math.max(
          (end.getTime() - start.getTime()) / 60000,
          WHATSAPP_BLOCK_MINUTES
        )
      : WHATSAPP_BLOCK_MINUTES;
  return (minutes / 60) * HOUR_HEIGHT;
};

const eventBlockStyle = event => ({
  top: `${topForEvent(event)}px`,
  height: `${heightForEvent(event)}px`,
});

const eventLabelClass = event =>
  isOverdue(event) ? 'text-n-ruby-11' : 'text-n-slate-12';

/* -------------------------------------------------------------------------- */
/* Live "now" line                                                            */
/* -------------------------------------------------------------------------- */
const now = ref(new Date());
let nowTimer = null;

// On mount, scroll the time-grid so the now-line (or the start of business
// hours) is in view rather than opening at 00:00.
const BUSINESS_START_HOUR = 8;
const scrollContainer = ref(null);

const scrollToNow = () => {
  const el = scrollContainer.value;
  if (!el) return;
  const focusHour = days.value.some(day => isSameDay(day, now.value))
    ? Math.max(getHours(now.value) - 1, 0)
    : BUSINESS_START_HOUR;
  el.scrollTop = focusHour * HOUR_HEIGHT;
};

onMounted(() => {
  nextTick(scrollToNow);
  nowTimer = setInterval(() => {
    now.value = new Date();
  }, 60 * 1000);
});

onBeforeUnmount(() => {
  if (nowTimer) clearInterval(nowTimer);
});

const nowLineStyle = computed(() => ({
  top: `${((getHours(now.value) * 60 + getMinutes(now.value)) / 60) * HOUR_HEIGHT}px`,
}));

const dayShowsNowLine = day => isSameDay(day, now.value);

/* -------------------------------------------------------------------------- */
/* Drag-to-reschedule (native HTML5, snap to 15 min, block past WhatsApp)     */
/* -------------------------------------------------------------------------- */
const draggingEvent = ref(null);
const dragOverKey = ref(null); // `${dayKey}#${hour}`

// Resolve the precise datetime for a drop, snapping minutes to SNAP_MINUTES.
const resolveDropDate = (day, nativeEvent, hour) => {
  let minutes = 0;
  if (typeof nativeEvent.offsetY === 'number') {
    const ratio = Math.min(
      Math.max(nativeEvent.offsetY / HOUR_HEIGHT, 0),
      0.999
    );
    minutes = Math.round((ratio * 60) / SNAP_MINUTES) * SNAP_MINUTES;
  }
  let result = setHours(startOfDay(day), hour);
  result = setMinutes(result, minutes);
  return result;
};

const onDragStart = (event, nativeEvent) => {
  if (!isDraggable(event)) {
    nativeEvent.preventDefault();
    return;
  }
  draggingEvent.value = event;
  if (nativeEvent.dataTransfer) {
    nativeEvent.dataTransfer.effectAllowed = 'move';
    nativeEvent.dataTransfer.setData('text/plain', String(event.id));
  }
};

const onDragEnd = () => {
  draggingEvent.value = null;
  dragOverKey.value = null;
};

const onCellDragOver = (day, hour, nativeEvent) => {
  const event = draggingEvent.value;
  if (!event) return;
  const target = resolveDropDate(day, nativeEvent, hour);
  if (!isValidDrop(event, target, now.value)) {
    if (nativeEvent.dataTransfer) nativeEvent.dataTransfer.dropEffect = 'none';
    return;
  }
  nativeEvent.preventDefault();
  if (nativeEvent.dataTransfer) nativeEvent.dataTransfer.dropEffect = 'move';
  dragOverKey.value = `${dayKey(day)}#${hour}`;
};

const onCellDragLeave = (day, hour) => {
  if (dragOverKey.value === `${dayKey(day)}#${hour}`) dragOverKey.value = null;
};

const onCellDrop = (day, hour, nativeEvent) => {
  const event = draggingEvent.value;
  draggingEvent.value = null;
  dragOverKey.value = null;
  if (!event) return;
  const startsAt = resolveDropDate(day, nativeEvent, hour);
  if (!isValidDrop(event, startsAt, now.value)) return;
  emit('eventDrop', { event, startsAt });
};

const isDropCell = (day, hour) =>
  dragOverKey.value === `${dayKey(day)}#${hour}`;

/* -------------------------------------------------------------------------- */
/* Clicks                                                                     */
/* -------------------------------------------------------------------------- */
const onSlotClick = (day, hour) => {
  emit('slotClick', { date: setHours(startOfDay(day), hour), hour });
};

const onEventClick = event => emit('eventClick', event);

const onAllDaySlotClick = day => {
  emit('slotClick', { date: startOfDay(day) });
};

const hourLabel = hour => `${String(hour).padStart(2, '0')}:00`;
</script>

<template>
  <div class="flex flex-col w-full h-full min-h-0 overflow-hidden">
    <!-- Day headers (Sunday-first) -->
    <div
      class="grid shrink-0 border-b border-n-weak grid-cols-[3.5rem_repeat(7,minmax(0,1fr))]"
    >
      <div class="border-r border-n-weak" />
      <div
        v-for="(day, idx) in days"
        :key="`hd-${dayKey(day)}`"
        class="flex flex-col items-center gap-0.5 px-1 py-2 border-r border-n-weak"
      >
        <span class="text-[10px] font-medium uppercase text-n-slate-10">
          {{ weekdayShort[idx] }}
        </span>
        <span
          class="inline-flex items-center justify-center font-semibold rounded-full size-7 text-sm"
          :class="
            isCurrentDay(day) ? 'bg-n-brand text-white' : 'text-n-slate-12'
          "
          :aria-label="dayAria(day)"
        >
          {{ dayNumber(day) }}
        </span>
      </div>
    </div>

    <!-- All-day row -->
    <div
      v-if="hasAnyAllDay"
      class="grid shrink-0 border-b border-n-weak bg-n-alpha-black2 grid-cols-[3.5rem_repeat(7,minmax(0,1fr))]"
    >
      <div
        class="flex items-start justify-end px-1 py-1 border-r border-n-weak"
      >
        <span class="text-[10px] font-medium text-n-slate-10">
          {{ t('CRM_KANBAN.CALENDAR.ALL_DAY') }}
        </span>
      </div>
      <div
        v-for="day in days"
        :key="`ad-${dayKey(day)}`"
        class="flex flex-col gap-0.5 p-1 border-r border-n-weak min-h-[2rem]"
        @click="onAllDaySlotClick(day)"
      >
        <button
          v-for="event in allDayEventsForDay(day)"
          :key="`ade-${event.id}`"
          type="button"
          :draggable="isDraggable(event)"
          class="flex items-center w-full gap-1 px-1 py-0.5 text-left rounded hover:bg-n-alpha-2"
          :class="{ 'cursor-grab': isDraggable(event) }"
          @click.stop="onEventClick(event)"
          @dragstart="onDragStart(event, $event)"
          @dragend="onDragEnd"
        >
          <span
            class="rounded-full size-1.5 shrink-0"
            :class="eventColorClass(event)"
          />
          <span class="text-xs truncate" :class="eventLabelClass(event)">
            {{ event.title }}
          </span>
        </button>
      </div>
    </div>

    <!-- Time grid (scrollable) -->
    <div ref="scrollContainer" class="relative flex-1 min-h-0 overflow-y-auto">
      <div class="grid grid-cols-[3.5rem_repeat(7,minmax(0,1fr))]">
        <!-- Hour gutter -->
        <div class="flex flex-col border-r border-n-weak">
          <div
            v-for="hour in hours"
            :key="`gh-${hour}`"
            class="relative h-12 pr-1 text-right"
          >
            <span
              class="absolute right-1 -top-1.5 text-[10px] tabular-nums text-n-slate-10"
            >
              {{ hour === 0 ? '' : hourLabel(hour) }}
            </span>
          </div>
        </div>

        <!-- Day columns -->
        <div
          v-for="day in days"
          :key="`col-${dayKey(day)}`"
          class="relative border-r border-n-weak"
          :class="isCurrentDay(day) ? 'bg-n-brand/5' : ''"
        >
          <!-- Hour cells (click + drop targets) -->
          <div
            v-for="hour in hours"
            :key="`cell-${dayKey(day)}-${hour}`"
            class="h-12 transition-colors border-b border-n-weak"
            :class="
              isDropCell(day, hour)
                ? 'bg-n-brand/10 ring-1 ring-inset ring-n-brand'
                : 'hover:bg-n-alpha-2'
            "
            @click="onSlotClick(day, hour)"
            @dragover="onCellDragOver(day, hour, $event)"
            @dragleave="onCellDragLeave(day, hour)"
            @drop.prevent="onCellDrop(day, hour, $event)"
          />

          <!-- Timed events (whatsapp sends) absolutely positioned -->
          <button
            v-for="event in timedEventsForDay(day)"
            :key="`te-${event.id}`"
            type="button"
            :draggable="isDraggable(event)"
            class="absolute z-10 flex items-start gap-1 px-1 py-0.5 overflow-hidden text-left border rounded shadow-sm inset-x-0.5 border-n-weak bg-n-surface-1 hover:bg-n-alpha-2"
            :class="{ 'cursor-grab': isDraggable(event) }"
            :style="eventBlockStyle(event)"
            @click.stop="onEventClick(event)"
            @dragstart="onDragStart(event, $event)"
            @dragend="onDragEnd"
          >
            <span
              class="mt-0.5 size-3 shrink-0"
              :class="[eventIconClass(event), eventTextClass(event)]"
            />
            <span class="flex flex-col min-w-0">
              <span class="text-[10px] tabular-nums text-n-slate-10">
                {{ eventTime(event) }}
              </span>
              <span class="text-xs truncate" :class="eventLabelClass(event)">
                {{ event.title }}
              </span>
            </span>
          </button>

          <!-- Live now-line -->
          <div
            v-if="dayShowsNowLine(day)"
            class="absolute inset-x-0 z-20 flex items-center pointer-events-none"
            :style="nowLineStyle"
            :aria-label="t('CRM_KANBAN.CALENDAR.NOW')"
          >
            <span class="-ml-1 rounded-full size-2 bg-n-ruby-11" />
            <span class="flex-1 h-px bg-n-ruby-11" />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
