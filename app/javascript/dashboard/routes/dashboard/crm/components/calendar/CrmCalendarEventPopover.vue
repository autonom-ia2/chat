<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { ptBR, enUS } from 'date-fns/locale';

import Button from 'dashboard/components-next/button/Button.vue';
import {
  EVENT_TYPE_GROUP,
  EVENT_TYPE_META,
  eventStart,
  isOverdue,
} from './calendarEvents.js';
import { resolveMeetingLocation } from '../../helpers/meetingLocation';

const props = defineProps({
  event: { type: Object, required: true },
  timezone: { type: String, default: '' },
});

const emit = defineEmits([
  'complete',
  'snooze',
  'reschedule',
  'openDeal',
  'edit',
  'cancel',
  'sendNow',
  'openConversation',
  'changeCloseDate',
  'win',
  'lose',
  'openCard',
]);

const { t, locale } = useI18n();

const dateFnsLocale = computed(() => (locale.value === 'pt_BR' ? ptBR : enUS));

const group = computed(() => EVENT_TYPE_GROUP(props.event.event_type));
const meta = computed(() => EVENT_TYPE_META[group.value]);

const typeKeyForGroup = {
  reminder: 'REMINDER',
  whatsapp: 'WHATSAPP',
  closeDate: 'CLOSE',
  meeting: 'MEETING',
};
const typeKey = computed(() => typeKeyForGroup[group.value]);

const overdue = computed(() => isOverdue(props.event, new Date()));

const startsAtLabel = computed(() =>
  format(eventStart(props.event), "dd/MM/yyyy 'às' HH:mm", {
    locale: dateFnsLocale.value,
  })
);

const isDone = computed(
  () => props.event.status === 'sent' || props.event.status === 'done'
);

const hasConversation = computed(() => Boolean(props.event.conversation_id));
const hasCard = computed(() => Boolean(props.event.card_id));
// Reunião interna mostra o local pelo rótulo próprio e só abre link http/https.
const location = computed(() => resolveMeetingLocation(props.event));
const hasJoinLink = computed(() => Boolean(location.value.joinUrl));

const snoozePresets = [
  { key: '1h', label: 'SNOOZE_1H' },
  { key: 'tomorrow', label: 'SNOOZE_TOMORROW' },
  { key: 'next_week', label: 'SNOOZE_NEXT_WEEK' },
];

const onOpenDeal = () => {
  emit('openDeal', props.event);
  emit('openCard', props.event);
};

const onJoinMeeting = () => {
  if (location.value.joinUrl) {
    window.open(location.value.joinUrl, '_blank', 'noopener,noreferrer');
  }
};
</script>

<template>
  <div class="flex w-72 flex-col gap-3 p-4">
    <header class="flex items-start gap-3">
      <span
        class="mt-0.5 flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2"
      >
        <span
          class="size-4"
          :class="[meta.icon, overdue ? 'text-n-ruby-11' : meta.textClass]"
        />
      </span>
      <div class="min-w-0 flex-1">
        <p class="mb-0.5 break-words text-sm font-medium text-n-slate-12">
          {{ event.title }}
        </p>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t(`CRM_KANBAN.CALENDAR.TYPE.${typeKey}`) }}
        </p>
      </div>
    </header>

    <div class="flex flex-col gap-1 text-xs">
      <p
        class="mb-0 flex items-center gap-1.5"
        :class="overdue ? 'text-n-ruby-11' : 'text-n-slate-11'"
      >
        <span class="i-lucide-clock size-3.5" />
        {{ startsAtLabel }}
      </p>
      <p
        v-if="group === 'meeting' && location.isInternal"
        class="mb-0 flex items-center gap-1.5 text-n-slate-11"
        data-test="meeting-location"
      >
        <span class="size-3.5" :class="location.icon" />
        {{ t(location.labelKey) }}
      </p>
      <p
        v-if="group === 'whatsapp' && timezone"
        class="mb-0 flex items-center gap-1.5 text-n-slate-11"
      >
        <span class="i-lucide-globe size-3.5" />
        {{ t('CRM_KANBAN.CALENDAR.TIMEZONE', { tz: timezone }) }}
      </p>
    </div>

    <div
      v-if="hasCard || hasConversation"
      class="flex flex-col gap-1 border-t border-n-weak pt-3"
    >
      <button
        v-if="hasCard"
        type="button"
        class="flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-xs text-n-slate-12 transition-colors hover:bg-n-alpha-2"
        @click="onOpenDeal"
      >
        <span class="i-lucide-briefcase size-3.5 text-n-slate-11" />
        <span class="truncate">{{
          t('CRM_KANBAN.CALENDAR.EVENT.OPEN_DEAL')
        }}</span>
        <span
          class="i-lucide-arrow-up-right ml-auto size-3.5 text-n-slate-10"
        />
      </button>
      <button
        v-if="hasConversation"
        type="button"
        class="flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-xs text-n-slate-12 transition-colors hover:bg-n-alpha-2"
        @click="emit('openConversation', event)"
      >
        <span class="i-lucide-messages-square size-3.5 text-n-slate-11" />
        <span class="truncate">
          {{ t('CRM_KANBAN.CALENDAR.EVENT.OPEN_CONVERSATION') }}
        </span>
        <span
          class="i-lucide-arrow-up-right ml-auto size-3.5 text-n-slate-10"
        />
      </button>
    </div>

    <!-- Reminder actions -->
    <div
      v-if="group === 'reminder'"
      class="flex flex-col gap-2 border-t border-n-weak pt-3"
    >
      <Button
        variant="solid"
        color="teal"
        size="sm"
        icon="i-lucide-check"
        :label="t('CRM_KANBAN.CALENDAR.EVENT.COMPLETE')"
        @click="emit('complete', event)"
      />
      <div class="flex flex-col gap-1">
        <p
          class="mb-0 px-1 text-[11px] font-medium uppercase tracking-wide text-n-slate-10"
        >
          {{ t('CRM_KANBAN.CALENDAR.EVENT.SNOOZE') }}
        </p>
        <div class="flex flex-wrap gap-1.5">
          <Button
            v-for="preset in snoozePresets"
            :key="preset.key"
            variant="outline"
            color="slate"
            size="xs"
            :label="t(`CRM_KANBAN.CALENDAR.EVENT.${preset.label}`)"
            @click="emit('snooze', { event, preset: preset.key })"
          />
        </div>
      </div>
      <Button
        variant="ghost"
        color="slate"
        size="sm"
        icon="i-lucide-calendar-clock"
        :label="t('CRM_KANBAN.CALENDAR.EVENT.RESCHEDULE')"
        @click="emit('reschedule', event)"
      />
    </div>

    <!-- WhatsApp actions -->
    <div
      v-else-if="group === 'whatsapp'"
      class="flex flex-col gap-2 border-t border-n-weak pt-3"
    >
      <template v-if="!isDone">
        <Button
          variant="solid"
          color="blue"
          size="sm"
          icon="i-lucide-send"
          :label="t('CRM_KANBAN.CALENDAR.EVENT.SEND_NOW')"
          @click="emit('sendNow', event)"
        />
        <div class="flex flex-wrap gap-1.5">
          <Button
            variant="outline"
            color="slate"
            size="xs"
            icon="i-lucide-pencil"
            :label="t('CRM_KANBAN.CALENDAR.EVENT.EDIT')"
            @click="emit('edit', event)"
          />
          <Button
            variant="outline"
            color="slate"
            size="xs"
            icon="i-lucide-calendar-clock"
            :label="t('CRM_KANBAN.CALENDAR.EVENT.RESCHEDULE')"
            @click="emit('reschedule', event)"
          />
          <Button
            variant="outline"
            color="ruby"
            size="xs"
            icon="i-lucide-x"
            :label="t('CRM_KANBAN.CALENDAR.EVENT.CANCEL')"
            @click="emit('cancel', event)"
          />
        </div>
      </template>
      <p v-else class="mb-0 px-1 text-xs text-n-slate-11">
        {{ t(`CRM_KANBAN.CALENDAR.TYPE.${typeKey}`) }}
      </p>
    </div>

    <!-- Meeting actions -->
    <div
      v-else-if="group === 'meeting'"
      class="flex flex-col gap-2 border-t border-n-weak pt-3"
    >
      <Button
        v-if="hasJoinLink"
        variant="solid"
        color="blue"
        size="sm"
        icon="i-lucide-video"
        :label="t('CRM_KANBAN.CALENDAR.EVENT.JOIN_MEETING')"
        @click="onJoinMeeting"
      />
      <Button
        v-if="hasCard"
        variant="ghost"
        color="slate"
        size="sm"
        icon="i-lucide-briefcase"
        :label="t('CRM_KANBAN.CALENDAR.EVENT.OPEN_DEAL')"
        @click="onOpenDeal"
      />
    </div>

    <!-- Expected close actions -->
    <div v-else class="flex flex-col gap-2 border-t border-n-weak pt-3">
      <div class="flex flex-wrap gap-1.5">
        <Button
          variant="solid"
          color="teal"
          size="xs"
          icon="i-lucide-trophy"
          :label="t('CRM_KANBAN.CALENDAR.EVENT.WIN')"
          @click="emit('win', event)"
        />
        <Button
          variant="outline"
          color="ruby"
          size="xs"
          icon="i-lucide-thumbs-down"
          :label="t('CRM_KANBAN.CALENDAR.EVENT.LOSE')"
          @click="emit('lose', event)"
        />
      </div>
      <Button
        variant="ghost"
        color="slate"
        size="sm"
        icon="i-lucide-calendar-clock"
        :label="t('CRM_KANBAN.CALENDAR.EVENT.CHANGE_DATE')"
        @click="emit('changeCloseDate', event)"
      />
    </div>
  </div>
</template>
