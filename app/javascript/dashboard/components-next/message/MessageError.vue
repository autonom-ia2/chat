<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from './provider.js';
import { useInbox } from 'dashboard/composables/useInbox';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { erroDaMeta } from 'dashboard/helper/erroDaMeta';
import { hasOneDayPassed } from 'shared/helpers/timeHelper';
import { ORIENTATION, MESSAGE_STATUS } from './constants';

const props = defineProps({
  error: { type: String, required: true },
  // Quem só lê a conversa (#1800) não reenvia.
  readOnly: { type: Boolean, default: false },
});

const emit = defineEmits(['retry']);

const { orientation, status, createdAt, content, attachments, inboxId } =
  useMessageContext();

const { t } = useI18n();

// chat#1655: erro da Meta em linguagem simples só em caixa Channel::Whatsapp.
const { inbox } = useInbox(inboxId?.value);
const meta = computed(() =>
  erroDaMeta(props.error, inbox.value?.channelType === INBOX_TYPES.WHATSAPP)
);

const canRetry = computed(() => {
  const hasContent = content.value !== null;
  const hasAttachments = attachments.value && attachments.value.length > 0;
  return (
    !props.readOnly &&
    meta.value.podeReenviar &&
    !hasOneDayPassed(createdAt.value) &&
    (hasContent || hasAttachments)
  );
});
</script>

<!-- chat#1473: o motivo fica escrito na conversa (no celular não existe passar o mouse) e o reenvio tem rótulo. -->
<template>
  <div
    class="flex flex-col gap-1.5 min-w-0 text-xs text-n-ruby-11"
    :class="orientation === ORIENTATION.RIGHT ? 'items-end' : 'items-start'"
  >
    <div class="flex items-start gap-1.5 max-w-lg min-w-0">
      <Icon
        icon="i-lucide-alert-triangle"
        class="size-[14px] mt-px flex-shrink-0"
      />
      <span v-if="meta.chave" class="min-w-0 [overflow-wrap:anywhere]">
        <span class="font-medium">{{ t('ERRO_DA_META.NAO_SAIU') }}</span>
        {{ t(`${meta.chave}.O_QUE`) }}
      </span>
      <span v-else class="min-w-0 [overflow-wrap:anywhere]">
        <span class="font-medium">
          {{
            t('RICH_MESSAGE.FAILURE.TITLE', {
              title: t('CHAT_LIST.FAILED_TO_SEND'),
            })
          }}
        </span>
        {{ error }}
      </span>
    </div>
    <template v-if="meta.chave">
      <p class="max-w-lg min-w-0 pl-5 text-n-slate-12 [overflow-wrap:anywhere]">
        <span class="font-medium">{{ t('ERRO_DA_META.O_QUE_FAZER') }}</span>
        {{ t(`${meta.chave}.FAZER`) }}
      </p>
      <details class="group max-w-lg min-w-0">
        <summary
          class="inline-flex items-center gap-1 min-h-11 px-1 rounded-lg list-none cursor-pointer font-medium text-n-slate-11 [&::-webkit-details-marker]:hidden focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          <Icon
            icon="i-lucide-chevron-right"
            class="size-[14px] flex-shrink-0 transition-transform group-open:rotate-90"
          />
          {{ t('ERRO_DA_META.DETALHE') }}
        </summary>
        <p
          class="px-2.5 py-2 rounded-lg font-mono bg-n-alpha-2 text-n-slate-12 [overflow-wrap:anywhere]"
        >
          {{ meta.detalhe }}
        </p>
      </details>
    </template>
    <button
      v-if="canRetry"
      type="button"
      :disabled="status !== MESSAGE_STATUS.FAILED"
      class="inline-flex items-center gap-1.5 min-h-11 px-3 rounded-lg bg-n-alpha-2 font-medium cursor-pointer disabled:cursor-not-allowed disabled:opacity-50"
      @click="emit('retry')"
    >
      <Icon icon="i-lucide-refresh-ccw" class="size-[14px] flex-shrink-0" />
      {{ t('RICH_MESSAGE.FAILURE.RETRY') }}
    </button>
  </div>
</template>
