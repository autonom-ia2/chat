<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  canCall,
  canRebook,
  canRemind,
  formatClientPhone,
  meetingIdOf,
} from '../../helpers/meetingDay';
import CrmMeetingCallButton from './CrmMeetingCallButton.vue';
import CrmMeetingRemindButton from './CrmMeetingRemindButton.vue';
import CrmMeetingRebook from './CrmMeetingRebook.vue';
import CrmMeetingPostMove from './CrmMeetingPostMove.vue';

// O dia da reunião (#1193, J4) no detalhe da reunião e no card: número do
// cliente, "Chamar no WhatsApp", "Lembrar", o link para marcar outro horário
// quando ele faltou e a etapa para onde o card vai depois de "Aconteceu".
const props = defineProps({
  meeting: { type: Object, required: true },
  accountId: { type: [String, Number], required: true },
  // Resposta de record_outcome: a oferta de mover o card (ou null).
  postMeeting: { type: Object, default: null },
});

const emit = defineEmits(['changed']);
const { t } = useI18n();

const id = computed(() => meetingIdOf(props.meeting));
const client = computed(() => props.meeting.client || {});
const phone = computed(() => formatClientPhone(client.value.phone));
const showCall = computed(
  () => props.meeting.status === 'scheduled' && canCall(props.meeting)
);
const showRemind = computed(() => canRemind(props.meeting));
const showRebook = computed(() => canRebook(props.meeting));
const locationType = computed(
  () =>
    props.meeting.location_type ||
    props.meeting.online_meeting_type ||
    'whatsapp_video'
);
</script>

<template>
  <section class="grid gap-3" data-test="meeting-day">
    <p
      v-if="phone"
      data-test="meeting-client-phone"
      class="mb-0 flex items-center gap-2 text-sm text-n-slate-12"
    >
      <span class="i-lucide-phone size-4 text-n-slate-10" aria-hidden="true" />
      <span class="text-xs text-n-slate-11">
        {{ t('CRM_KANBAN.CALENDAR.MEETING_DAY.PHONE_LABEL') }}
      </span>
      <span dir="ltr">{{ phone }}</span>
    </p>
    <CrmMeetingCallButton
      v-if="showCall"
      :client="client"
      :account-id="accountId"
      :location-type="locationType"
    />
    <CrmMeetingRemindButton
      v-if="showRemind"
      :meeting-id="id"
      :account-id="accountId"
      @reminded="emit('changed')"
    />
    <CrmMeetingRebook
      v-if="showRebook"
      :meeting-id="id"
      :account-id="accountId"
      :client-name="client.name || ''"
      @sent="emit('changed')"
    />
    <CrmMeetingPostMove
      v-if="postMeeting && postMeeting.stage && meeting.card_id"
      :post-meeting="postMeeting"
      :card-id="meeting.card_id"
      @moved="emit('changed')"
    />
  </section>
</template>
