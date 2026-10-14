<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { format } from 'date-fns';
import { eventStart } from './calendarEvents.js';
import { resolveMeetingLocation } from '../../helpers/meetingLocation';
import { confirmationMeta } from '../../helpers/meetingNotices';
import { canRemind, meetingIdOf } from '../../helpers/meetingDay';
import CrmMeetingRemindButton from './CrmMeetingRemindButton.vue';

// Uma reunião na agenda de hoje (#1193): hora, local e se o cliente confirmou,
// pediu para mudar ou ainda não respondeu. Reunião de página de agendamento
// sem resposta ganha o "Lembrar" ao lado, sem abrir o detalhe.
const props = defineProps({
  event: { type: Object, required: true },
});

const emit = defineEmits(['open']);
const { t } = useI18n();
const route = useRoute();
const accountId = computed(() => route.params.accountId);

const time = computed(() => format(eventStart(props.event), 'HH:mm'));
const location = computed(() => resolveMeetingLocation(props.event));
const status = computed(() =>
  props.event.booking ? confirmationMeta(props.event.confirmation_status) : null
);
const showRemind = computed(() => canRemind(props.event));
</script>

<template>
  <div
    data-test="agenda-meeting"
    :data-status="event.confirmation_status"
    class="grid gap-2 rounded-lg border border-n-weak bg-n-surface-2 p-3"
  >
    <button
      type="button"
      class="grid min-h-11 w-full grid-cols-[auto_1fr_auto] items-start gap-3 rounded-md text-left transition-colors hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('open', event)"
    >
      <span
        class="mt-0.5 flex size-8 items-center justify-center rounded-lg bg-n-alpha-2"
      >
        <span
          class="size-4 text-n-iris-11"
          :class="location.isInternal ? location.icon : 'i-lucide-video'"
          aria-hidden="true"
        />
      </span>
      <span class="min-w-0">
        <span class="block truncate text-sm font-medium text-n-slate-12">
          {{ event.title }}
        </span>
        <span
          v-if="location.isInternal"
          class="block truncate text-xs text-n-slate-11"
        >
          {{ t(location.labelKey) }}
        </span>
      </span>
      <span class="whitespace-nowrap text-xs font-medium text-n-slate-12">
        {{ time }}
      </span>
    </button>
    <div
      v-if="status || showRemind"
      class="flex flex-wrap items-center justify-between gap-2"
    >
      <span
        v-if="status"
        data-test="agenda-meeting-status"
        class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-[11px] font-medium"
        :class="status.className"
      >
        <span class="size-3.5" :class="status.icon" aria-hidden="true" />
        {{ t(`CRM_KANBAN.CALENDAR.MEETING_DETAIL.CLIENT.${status.key}`) }}
      </span>
      <CrmMeetingRemindButton
        v-if="showRemind && accountId"
        compact
        :meeting-id="meetingIdOf(event)"
        :account-id="accountId"
      />
    </div>
  </div>
</template>
