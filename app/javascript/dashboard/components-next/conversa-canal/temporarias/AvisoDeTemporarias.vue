<script setup>
// Aviso de mensagens temporárias com a cara do WhatsApp (#1709): a etiqueta do meio
// da conversa, com o relógio, "Mensagens temporárias ativadas. Novas mensagens vão
// desaparecer desta conversa após 7 dias." (ou "desativadas"). Embaixo, que aqui a
// equipe continua vendo tudo: o painel guarda o que o cliente mandou. Quem escolhe é
// Message.vue, com a pele, para o aviso que traz waha_ephemeral.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from '../../message/bubbles/Base.vue';
import { useMessageContext } from '../../message/provider.js';
import { avisoDeTemporarias } from './temporarias';

const { contentAttributes } = useMessageContext();
const { t } = useI18n();

const aviso = computed(() => avisoDeTemporarias(contentAttributes.value));

const texto = computed(() => {
  if (!aviso.value.ligadas) return t('CONVERSA_CANAL.TEMPORARIAS.DESATIVADAS');
  const { dias, horas } = aviso.value;
  const duracao = dias
    ? t('CONVERSA_CANAL.TEMPORARIAS.DIAS', { n: dias }, dias)
    : t('CONVERSA_CANAL.TEMPORARIAS.HORAS', { n: horas }, horas);
  return t('CONVERSA_CANAL.TEMPORARIAS.ATIVADAS', { duracao });
});
</script>

<template>
  <BaseBubble
    class="px-3 py-1.5 max-w-[420px] flex items-start gap-2"
    data-bubble-name="activity"
    :data-aviso-de-temporarias="aviso.ligadas ? 'ligadas' : 'desligadas'"
  >
    <span
      class="i-ph-timer size-4 mt-px shrink-0 text-[#3B3B3B] dark:text-[#A7A8A8]"
      aria-hidden="true"
    />
    <span class="min-w-0">
      <span class="block">{{ texto }}</span>
      <span v-if="aviso.ligadas" class="block" data-temporarias-guardadas>
        {{ t('CONVERSA_CANAL.TEMPORARIAS.GUARDADAS') }}
      </span>
    </span>
  </BaseBubble>
</template>
