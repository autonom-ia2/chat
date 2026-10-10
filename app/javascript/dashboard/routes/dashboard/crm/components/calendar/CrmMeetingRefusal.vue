<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

// Por que a mensagem ao cliente não saiu (#1193), em frase leiga. Quando o
// servidor devolve o link do cliente (janela fechada, sem conversa), oferece
// copiar para o agente mandar de outro jeito.
const props = defineProps({
  // { key, url } de refusalFrom (helpers/meetingDay).
  refusal: { type: Object, required: true },
});

const { t } = useI18n();
const copied = ref(false);

const copy = async () => {
  try {
    await copyTextToClipboard(props.refusal.url);
    copied.value = true;
  } catch {
    copied.value = false;
  }
};
</script>

<template>
  <div
    role="alert"
    data-test="meeting-day-refusal"
    :data-refusal="refusal.key"
    class="grid gap-2 rounded-lg bg-n-amber-9/10 p-3 text-sm text-n-amber-12"
  >
    <p class="mb-0">
      {{ t(`CRM_KANBAN.CALENDAR.MEETING_DAY.REFUSED.${refusal.key}`) }}
    </p>
    <button
      v-if="refusal.url"
      type="button"
      data-test="meeting-day-copy"
      class="inline-flex min-h-11 items-center justify-center gap-2 self-start rounded-lg bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 outline outline-1 outline-n-weak hover:bg-n-alpha-2 focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="copy"
    >
      <span class="i-lucide-copy size-4" aria-hidden="true" />
      {{
        copied
          ? t('CRM_KANBAN.CALENDAR.MEETING_DAY.COPIED')
          : t('CRM_KANBAN.CALENDAR.MEETING_DAY.COPY_LINK')
      }}
    </button>
  </div>
</template>
