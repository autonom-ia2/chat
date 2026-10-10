<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import { refusalFrom } from '../../helpers/meetingDay';
import CrmMeetingRefusal from './CrmMeetingRefusal.vue';

// O cliente faltou (#1193, J4-A6): "Enviar link para marcar outro horário".
// Um toque cria o link do cliente e manda na conversa (mesmas regras do botão
// Agendar). "Agora não" só fecha a pergunta: nada sai sem o toque.
const props = defineProps({
  meetingId: { type: [String, Number], required: true },
  accountId: { type: [String, Number], required: true },
  clientName: { type: String, default: '' },
});

const emit = defineEmits(['sent']);
const { t } = useI18n();

const dismissed = ref(false);
const sending = ref(false);
const sent = ref(false);
const refusal = ref(null);

const firstName = computed(() => props.clientName.trim().split(' ')[0] || '');

const title = computed(() =>
  firstName.value
    ? t('CRM_KANBAN.CALENDAR.MEETING_DAY.REBOOK_TITLE', {
        name: firstName.value,
      })
    : t('CRM_KANBAN.CALENDAR.MEETING_DAY.REBOOK_TITLE_NO_NAME')
);

const send = async () => {
  if (sending.value) return;
  sending.value = true;
  refusal.value = null;
  try {
    const { data } = await crmMeetingsAPI.rebookLink(
      props.accountId,
      props.meetingId
    );
    sent.value = true;
    emit('sent', data?.payload || {});
  } catch (error) {
    refusal.value = refusalFrom(error);
  } finally {
    sending.value = false;
  }
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <section
    v-if="!dismissed"
    data-test="meeting-rebook"
    class="grid gap-3 rounded-lg border border-n-blue-7 bg-n-blue-9/5 p-3"
  >
    <p class="mb-0 text-sm font-medium text-n-slate-12">{{ title }}</p>
    <p v-if="sent" role="status" class="mb-0 text-sm text-n-teal-11">
      {{ t('CRM_KANBAN.CALENDAR.MEETING_DAY.REBOOK_SENT') }}
    </p>
    <div v-else class="flex flex-wrap gap-2">
      <button
        type="button"
        data-test="meeting-rebook-send"
        class="inline-flex min-h-11 items-center gap-2 rounded-lg bg-n-brand px-4 text-sm font-medium text-white hover:bg-n-brand/90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
        :disabled="sending"
        :aria-busy="sending"
        @click="send"
      >
        <span class="i-lucide-send size-4" aria-hidden="true" />
        {{ t('CRM_KANBAN.CALENDAR.MEETING_DAY.REBOOK_SEND') }}
      </button>
      <button
        type="button"
        data-test="meeting-rebook-dismiss"
        class="inline-flex min-h-11 items-center rounded-lg px-4 text-sm font-medium text-n-slate-12 outline outline-1 outline-n-weak hover:bg-n-alpha-2 focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="dismissed = true"
      >
        {{ t('CRM_KANBAN.CALENDAR.MEETING_DAY.NOT_NOW') }}
      </button>
    </div>
    <CrmMeetingRefusal v-if="refusal" :refusal="refusal" />
  </section>
</template>
