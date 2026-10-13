<script setup>
// Formulário do WhatsApp (Flow): `{ type: 'flow', flowId, cta, token, screen, data?, mode?, header?, footer?, name? }`,
// com o corpo em `content`. Mostra o que o cliente vê (corpo, cabeçalho, rodapé e o botão) e o nome do formulário.
// Nunca lê `data` nem `token`: os dados iniciais não aparecem na conversa do atendente.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../../../provider.js';
import Frame from '../Frame.vue';
import ActionRow from '../ActionRow.vue';

const { contentAttributes } = useMessageContext();
const { t } = useI18n();

// Os campos vêm de quem chamou a API: só texto entra na tela.
const textOf = value => (typeof value === 'string' ? value : '');

const richMessage = computed(() => contentAttributes.value?.richMessage ?? {});
const name = computed(() => textOf(richMessage.value.name).trim());
const sentLabel = computed(() =>
  name.value
    ? t('RICH_MESSAGE.FLOW.SENT_NAMED', { name: name.value })
    : t('RICH_MESSAGE.FLOW.SENT')
);
</script>

<template>
  <Frame
    bubble-name="rich-flow"
    :header="textOf(richMessage.header)"
    :footer="textOf(richMessage.footer)"
  >
    <div class="flex flex-col gap-1.5">
      <ActionRow
        icon="i-lucide-clipboard-list"
        :label="textOf(richMessage.cta)"
      />
      <div class="text-xs text-n-slate-11 break-words">
        {{ sentLabel }}
      </div>
    </div>
  </Frame>
</template>
