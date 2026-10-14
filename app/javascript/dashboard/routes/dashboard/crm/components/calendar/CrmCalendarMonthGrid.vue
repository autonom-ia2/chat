<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { isSameMonth, isToday as dateFnsIsToday, format } from 'date-fns';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import {
  monthMatrix,
  weekdayLabels,
  eventsForDay,
  eventColorClass,
  isOverdue,
  isDraggable,
  isValidDrop,
  formatTime,
  EVENT_TYPE_GROUP,
  EVENT_TYPE_META,
  ptBR,
} from './calendarEvents.js';
import {
  isInternalMeeting,
  resolveMeetingLocation,
} from '../../helpers/meetingLocation';

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
      external: true,
    }),
  },
});

const emit = defineEmits(['dayClick', 'eventClick', 'slotClick', 'eventDrop']);

const { t } = useI18n();

const MAX_VISIBLE = 2;
const MEETING_GROUP = 'meeting';
const MEETING_META = {
  group: MEETING_GROUP,
  icon: 'i-logos-google-meet',
  dotClass: 'bg-n-iris-9',
  textClass: 'text-n-iris-11',
  pillClass: 'bg-n-iris-9/10 text-n-iris-12',
  overlayKey: 'meetings',
};

const weeks = computed(() => monthMatrix(props.cursorDate));
const weekdays = computed(() => weekdayLabels('EEEEEE'));

// Defensively respect the overlay toggles even though the parent pre-filters.
const isMeetingEvent = event => event?.event_type === 'meeting';
// External events are READ-ONLY availability context (the agent's own calendar):
// rendered muted/dashed, never clickable into a card/detail, never draggable.
const isExternalEvent = event => event?.event_type === 'external';

// Reunião interna não tem Meet nem Teams: ícone e dica do local próprio.
// Google e Microsoft seguem com o ícone da marca.
const INTERNAL_GROUP_ICON = 'i-lucide-calendar-clock';

const meetingIconClass = event => {
  const location = resolveMeetingLocation(event);
  if (location.isInternal) return location.icon;
  return event?.provider === 'microsoft' ||
    event?.online_meeting_type === 'teams'
    ? 'i-logos-microsoft-teams'
    : 'i-logos-google-meet';
};

const meetingLocationLabel = event => {
  const location = resolveMeetingLocation(event);
  return location.isInternal ? t(location.labelKey) : undefined;
};

const groupForEvent = event =>
  isMeetingEvent(event) ? MEETING_GROUP : EVENT_TYPE_GROUP(event.event_type);

const metaForGroup = group =>
  group === MEETING_GROUP ? MEETING_META : EVENT_TYPE_META[group];

const metaForEvent = event => metaForGroup(groupForEvent(event));

const filterEventsByOverlays = (events = [], overlays = {}) =>
  events.filter(event => overlays[metaForEvent(event).overlayKey] !== false);

const shownEvents = computed(() =>
  filterEventsByOverlays(props.events, props.overlays)
);

const dayKey = day => format(day, 'yyyy-MM-dd');

const isOutsideMonth = day => !isSameMonth(day, props.cursorDate);
const isCurrentDay = day => dateFnsIsToday(day);

const dayLabel = day => format(day, 'd', { locale: ptBR });
const fullDayLabel = day => format(day, "EEEE, d 'de' MMMM", { locale: ptBR });

// Memoize the per-day event list once per render (keyed by yyyy-MM-dd) so the
// consumers below — dayCount, isDense, dayGroups and the dense-day popover —
// share a single eventsForDay pass instead of recomputing it each.
const eventsByDayKey = computed(() => {
  const map = {};
  weeks.value.forEach(week => {
    week.forEach(day => {
      map[dayKey(day)] = eventsForDay(shownEvents.value, day);
    });
  });
  return map;
});

const dayEvents = day => eventsByDayKey.value[dayKey(day)] || [];
const dayCount = day => dayEvents(day).length;

// Light days list their events; dense days collapse into per-type count chips
// (kills the "+154 more" dead-end — the day reads as its shape, not a wall).
const DENSE_THRESHOLD = MAX_VISIBLE + 1;
const isDense = day => dayCount(day) > DENSE_THRESHOLD;
const aggregateEventsByGroup = (events = []) => {
  const counts = {};
  const internalCounts = {};
  events.forEach(event => {
    const group = groupForEvent(event);
    counts[group] = (counts[group] || 0) + 1;
    if (isMeetingEvent(event) && isInternalMeeting(event))
      internalCounts[group] = (internalCounts[group] || 0) + 1;
  });
  return Object.entries(counts)
    .map(([group, count]) => ({
      group,
      count,
      meta: metaForGroup(group),
      // Só reuniões internas no dia: o chip não pode mostrar o ícone do Meet.
      icon:
        internalCounts[group] === count
          ? INTERNAL_GROUP_ICON
          : metaForGroup(group).icon,
    }))
    .sort((a, b) => b.count - a.count);
};

const dayGroups = day => aggregateEventsByGroup(dayEvents(day));

// Subtle heatmap tint so busy days surface at a glance (neutral, never clashes
// with the type chips). Two intensity steps + nothing for quiet days.
const densityClass = day => {
  const n = dayCount(day);
  if (n >= 20) return 'bg-n-alpha-2';
  if (n >= DENSE_THRESHOLD + 1) return 'bg-n-alpha-1';
  return '';
};

const eventDotClass = event =>
  isMeetingEvent(event) ? MEETING_META.dotClass : eventColorClass(event);
const eventTitle = event => event.title || '';

// Hover tooltip — external events surface the read-only context copy so the
// muted styling reads as "your calendar", not a broken/clickable CRM event.
const eventTooltip = event =>
  isExternalEvent(event)
    ? `${eventTitle(event) || t('CRM_KANBAN.CALENDAR.EXTERNAL_EVENT')} · ${t('CRM_KANBAN.CALENDAR.EXTERNAL_TOOLTIP')}`
    : eventTitle(event);

const eventLabelClass = event => {
  if (isExternalEvent(event)) return 'text-n-slate-10 italic';
  if (isOverdue(event)) return 'text-n-ruby-11';
  if (isMeetingEvent(event)) return 'text-n-iris-12';
  return 'text-n-slate-12';
};

const eventButtonClass = event => {
  if (isExternalEvent(event))
    return 'bg-n-alpha-1 outline-dashed outline-1 outline-n-slate-6 cursor-default hover:bg-n-alpha-2';
  if (isMeetingEvent(event)) return 'bg-n-iris-9/10 hover:bg-n-iris-9/20';
  return '';
};

const eventIsDraggable = event =>
  !isMeetingEvent(event) && !isExternalEvent(event) && isDraggable(event);

/* -------------------------------------------------------------------------- */
/* Drag-to-reschedule (native HTML5)                                          */
/* -------------------------------------------------------------------------- */

const draggingEvent = ref(null);
const dragOverKey = ref(null);

const onDragStart = (event, nativeEvent) => {
  if (!eventIsDraggable(event)) {
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

const canDropOn = day => {
  const event = draggingEvent.value;
  if (!event) return false;
  return isValidDrop(event, day);
};

const onDragOver = (day, nativeEvent) => {
  if (!draggingEvent.value) return;
  if (!canDropOn(day)) {
    if (nativeEvent.dataTransfer) nativeEvent.dataTransfer.dropEffect = 'none';
    return;
  }
  nativeEvent.preventDefault();
  if (nativeEvent.dataTransfer) nativeEvent.dataTransfer.dropEffect = 'move';
  dragOverKey.value = dayKey(day);
};

const onDragLeave = day => {
  if (dragOverKey.value === dayKey(day)) dragOverKey.value = null;
};

const onDrop = day => {
  const event = draggingEvent.value;
  draggingEvent.value = null;
  dragOverKey.value = null;
  if (!event || !canDropOn(day)) return;
  emit('eventDrop', { event, date: day });
};

const isDropTarget = day => dragOverKey.value === dayKey(day);

/* -------------------------------------------------------------------------- */
/* Click handlers                                                             */
/* -------------------------------------------------------------------------- */

const onSlotClick = day => {
  emit('slotClick', { date: day });
};

const onDayNumberClick = day => {
  emit('dayClick', day);
};

const onEventClick = event => {
  // External events are read-only context — clicking does nothing (the title
  // tooltip is the only affordance). Never open a card/detail/scheduler.
  if (isExternalEvent(event)) return;
  emit('eventClick', event);
};
</script>

<template>
  <div class="flex flex-col w-full h-full min-h-0">
    <div class="grid grid-cols-7 border-b border-n-weak shrink-0">
      <div
        v-for="(label, idx) in weekdays"
        :key="`wd-${idx}`"
        class="px-2 py-2 text-xs font-medium text-center uppercase text-n-slate-10 truncate"
      >
        {{ label }}
      </div>
    </div>

    <div
      class="grid flex-1 grid-cols-7 auto-rows-[minmax(7rem,1fr)] min-h-0 overflow-y-auto"
    >
      <template v-for="(week, wIdx) in weeks" :key="`w-${wIdx}`">
        <div
          v-for="day in week"
          :key="dayKey(day)"
          class="flex flex-col min-h-[7rem] gap-1 p-1 border-b border-r border-n-weak transition-colors"
          :class="[
            isOutsideMonth(day)
              ? 'bg-n-alpha-black2'
              : densityClass(day) || 'bg-n-surface-1',
            isDropTarget(day)
              ? 'ring-2 ring-inset ring-n-brand bg-n-brand/5'
              : '',
          ]"
          @click="onSlotClick(day)"
          @dragover="onDragOver(day, $event)"
          @dragleave="onDragLeave(day)"
          @drop.prevent="onDrop(day)"
        >
          <div class="flex items-center justify-between px-1 shrink-0">
            <button
              type="button"
              class="inline-flex items-center justify-center w-6 h-6 text-xs font-medium rounded-full hover:bg-n-alpha-2"
              :class="[
                isCurrentDay(day)
                  ? 'bg-n-brand text-white'
                  : isOutsideMonth(day)
                    ? 'text-n-slate-9'
                    : 'text-n-slate-11',
              ]"
              :aria-label="fullDayLabel(day)"
              @click.stop="onDayNumberClick(day)"
            >
              {{ dayLabel(day) }}
            </button>
          </div>

          <div class="flex flex-col gap-0.5 min-h-0">
            <!-- Light day: list each event -->
            <template v-if="!isDense(day)">
              <button
                v-for="event in dayEvents(day)"
                :key="event.id"
                type="button"
                :draggable="eventIsDraggable(event)"
                :title="eventTooltip(event)"
                class="flex items-center w-full gap-1 px-1 py-0.5 text-left rounded cursor-pointer hover:bg-n-alpha-2"
                :class="[
                  eventButtonClass(event),
                  { 'cursor-grab': eventIsDraggable(event) },
                ]"
                @click.stop="onEventClick(event)"
                @dragstart="onDragStart(event, $event)"
                @dragend="onDragEnd"
              >
                <span
                  class="w-1.5 h-1.5 rounded-full shrink-0"
                  :class="eventDotClass(event)"
                />
                <span
                  v-if="isMeetingEvent(event)"
                  class="size-3.5 shrink-0"
                  :class="meetingIconClass(event)"
                  :title="meetingLocationLabel(event)"
                  aria-hidden="true"
                />
                <span
                  v-else-if="isExternalEvent(event)"
                  class="i-lucide-calendar size-3.5 shrink-0 text-n-slate-9"
                  aria-hidden="true"
                />
                <span
                  v-if="formatTime(event.starts_at)"
                  class="text-[10px] tabular-nums shrink-0 text-n-slate-10"
                >
                  {{ formatTime(event.starts_at) }}
                </span>
                <span class="text-xs truncate" :class="eventLabelClass(event)">
                  {{ eventTitle(event) }}
                </span>
              </button>
            </template>

            <!-- Dense day: per-type count chips → popover with full grouped list.
                 Wrapper stops the click bubbling to the cell (slot-click) AFTER the
                 Popover's own trigger toggles it open. -->
            <div
              v-else
              class="w-full [&>span]:flex [&>span]:w-full"
              @click.stop
            >
              <Popover align="start">
                <template #default>
                  <button
                    type="button"
                    class="flex flex-col w-full gap-0.5 text-left"
                    :aria-label="
                      t('CRM_KANBAN.CALENDAR.DENSE_SUMMARY', {
                        n: dayCount(day),
                      })
                    "
                  >
                    <span
                      v-for="g in dayGroups(day)"
                      :key="g.group"
                      class="flex items-center w-full gap-1.5 rounded px-1.5 py-0.5 text-xs font-medium tabular-nums"
                      :class="g.meta.pillClass"
                    >
                      <span class="size-3.5 shrink-0" :class="g.icon" />
                      {{ g.count }}
                    </span>
                  </button>
                </template>
                <template #content="{ hide }">
                  <div
                    class="flex flex-col gap-1 p-3 w-72 max-h-80 overflow-y-auto"
                  >
                    <div class="px-1 pb-1">
                      <p class="mb-0 text-xs font-medium text-n-slate-11">
                        {{ fullDayLabel(day) }}
                      </p>
                      <p class="mb-0 text-[11px] text-n-slate-10">
                        {{
                          t('CRM_KANBAN.CALENDAR.DENSE_SUMMARY', {
                            n: dayCount(day),
                          })
                        }}
                      </p>
                    </div>
                    <button
                      v-for="event in dayEvents(day)"
                      :key="`more-${event.id}`"
                      type="button"
                      :title="eventTooltip(event)"
                      class="flex items-center w-full gap-2 px-2 py-1.5 text-left rounded-md hover:bg-n-alpha-2"
                      :class="eventButtonClass(event)"
                      @click.stop="
                        onEventClick(event);
                        hide();
                      "
                    >
                      <span
                        class="w-2 h-2 rounded-full shrink-0"
                        :class="eventDotClass(event)"
                      />
                      <span
                        v-if="isMeetingEvent(event)"
                        class="size-3.5 shrink-0"
                        :class="meetingIconClass(event)"
                        :title="meetingLocationLabel(event)"
                        aria-hidden="true"
                      />
                      <span
                        v-else-if="isExternalEvent(event)"
                        class="i-lucide-calendar size-3.5 shrink-0 text-n-slate-9"
                        aria-hidden="true"
                      />
                      <span
                        v-if="formatTime(event.starts_at)"
                        class="text-[11px] tabular-nums shrink-0 text-n-slate-10"
                      >
                        {{ formatTime(event.starts_at) }}
                      </span>
                      <span
                        class="text-sm truncate"
                        :class="eventLabelClass(event)"
                      >
                        {{ eventTitle(event) }}
                      </span>
                    </button>
                  </div>
                </template>
              </Popover>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
