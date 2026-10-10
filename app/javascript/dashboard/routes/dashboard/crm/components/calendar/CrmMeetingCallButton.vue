<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

// "Chamar no WhatsApp" (#1193, J4-A2). Com conversa de WhatsApp do cliente que
// a pessoa pode abrir, abre essa conversa no painel; senão abre o WhatsApp no
// número da reunião (wa.me). A chamada de vídeo ou de voz começa no próprio
// WhatsApp: o texto diz onde tocar.
const props = defineProps({
  // { phone, whatsapp_url, conversation_id } do detalhe da reunião.
  client: { type: Object, required: true },
  accountId: { type: [String, Number], required: true },
  locationType: { type: String, default: 'whatsapp_video' },
});

const emit = defineEmits(['opened']);
const { t } = useI18n();
const router = useRouter();

const hintKey = computed(() =>
  props.locationType === 'whatsapp_voice' ? 'CALL_HINT_VOICE' : 'CALL_HINT'
);

const call = () => {
  if (props.client.conversation_id) {
    router.push({
      name: 'inbox_conversation',
      params: {
        accountId: props.accountId,
        conversation_id: props.client.conversation_id,
      },
    });
  } else if (props.client.whatsapp_url) {
    window.open(props.client.whatsapp_url, '_blank', 'noopener,noreferrer');
  }
  emit('opened');
};
</script>

<template>
  <div class="grid gap-2" data-test="meeting-call">
    <button
      type="button"
      data-test="meeting-call-button"
      class="inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-lg bg-n-teal-9 px-4 text-sm font-medium text-white transition-colors hover:bg-n-teal-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="call"
    >
      <span class="i-lucide-message-circle size-5" aria-hidden="true" />
      {{ t('CRM_KANBAN.CALENDAR.MEETING_DAY.CALL') }}
    </button>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t(`CRM_KANBAN.CALENDAR.MEETING_DAY.${hintKey}`) }}
    </p>
  </div>
</template>
