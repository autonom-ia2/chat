<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import { refusalFrom } from '../../helpers/meetingDay';
import CrmMeetingRefusal from './CrmMeetingRefusal.vue';

// "Lembrar" (#1193, J4-A5): com um toque, manda ao cliente, na conversa, uma
// mensagem curta pedindo para confirmar o horário pelo link dele. Nada sai
// sozinho; se não puder sair, explica e oferece copiar o link.
const props = defineProps({
  meetingId: { type: [String, Number], required: true },
  accountId: { type: [String, Number], required: true },
  // Na agenda de hoje: só o botão, sem a frase de ajuda.
  compact: { type: Boolean, default: false },
});

const emit = defineEmits(['reminded']);
const { t } = useI18n();

const sending = ref(false);
const sent = ref(false);
const refusal = ref(null);

const remind = async () => {
  if (sending.value || sent.value) return;
  sending.value = true;
  refusal.value = null;
  try {
    const { data } = await crmMeetingsAPI.remind(
      props.accountId,
      props.meetingId
    );
    sent.value = true;
    emit('reminded', data?.payload || {});
  } catch (error) {
    refusal.value = refusalFrom(error);
  } finally {
    sending.value = false;
  }
};
</script>

<template>
  <div class="grid gap-2" data-test="meeting-remind">
    <button
      type="button"
      data-test="meeting-remind-button"
      class="inline-flex min-h-11 items-center justify-center gap-2 rounded-lg px-4 text-sm font-medium outline outline-1 transition-colors focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
      :class="
        sent
          ? 'bg-n-teal-9/10 text-n-teal-11 outline-n-teal-9/40'
          : 'bg-n-solid-1 text-n-slate-12 outline-n-weak hover:bg-n-alpha-2'
      "
      :disabled="sending || sent"
      :aria-busy="sending"
      @click="remind"
    >
      <span
        class="size-4"
        :class="sent ? 'i-lucide-check' : 'i-lucide-bell-ring'"
        aria-hidden="true"
      />
      {{
        sent
          ? t('CRM_KANBAN.CALENDAR.MEETING_DAY.REMIND_SENT')
          : t('CRM_KANBAN.CALENDAR.MEETING_DAY.REMIND')
      }}
    </button>
    <p
      v-if="!compact && !sent && !refusal"
      class="mb-0 text-xs text-n-slate-11"
    >
      {{ t('CRM_KANBAN.CALENDAR.MEETING_DAY.REMIND_HINT') }}
    </p>
    <p v-if="sent" role="status" class="mb-0 text-xs text-n-teal-11">
      {{ t('CRM_KANBAN.CALENDAR.MEETING_DAY.REMIND_SENT_HINT') }}
    </p>
    <CrmMeetingRefusal v-if="refusal" :refusal="refusal" />
  </div>
</template>
