<script setup>
// Fim da conversa de e-mail (#1786): Responder, Responder a todos e Encaminhar, como
// no leitor de e-mail. Cada botão avisa a caixa de resposta, que já sabe montar os
// destinatários (getRecipients) e envia pelo mesmo caminho de sempre.
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { emitter } from 'shared/helpers/mitt';
import { MODOS_DE_RESPOSTA, RESPONDER_EMAIL } from './useConversaDeEmail';
import { PILULA } from './visualEmail';

const { t } = useI18n();

const ACOES = [
  {
    modo: MODOS_DE_RESPOSTA.RESPONDER,
    chave: 'RESPONDER',
    icone: 'i-lucide-reply',
  },
  {
    modo: MODOS_DE_RESPOSTA.TODOS,
    chave: 'RESPONDER_TODOS',
    icone: 'i-lucide-reply-all',
  },
  {
    modo: MODOS_DE_RESPOSTA.ENCAMINHAR,
    chave: 'ENCAMINHAR',
    icone: 'i-lucide-forward',
  },
];

const agir = modo => emitter.emit(RESPONDER_EMAIL, { modo });
</script>

<template>
  <li
    class="list-none w-full max-w-[960px] mx-auto flex flex-wrap gap-3 py-6 ps-[60px] sm:ps-[68px] pe-2"
    data-acoes-do-email
  >
    <button
      v-for="acao in ACOES"
      :key="acao.modo"
      type="button"
      :class="PILULA"
      :data-acao-do-email="acao.modo"
      @click="agir(acao.modo)"
    >
      <Icon :icon="acao.icone" class="size-4" />
      {{ t(`CONVERSA_CANAL.EMAIL.${acao.chave}`) }}
    </button>
  </li>
</template>
