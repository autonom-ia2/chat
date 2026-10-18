<script setup>
// Barra de responder da conversa de e-mail (#1786): Responder, Responder a todos,
// Encaminhar e Nota privada. Fica presa no rodapé da conversa enquanto o atendente lê,
// mesmo num e-mail longo (Rodrigo, 18/10). Cada botão avisa a caixa de resposta, que já sabe montar os
// destinatários (getRecipients) e envia pelo mesmo caminho de sempre.
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { emitter } from 'shared/helpers/mitt';
import {
  MODOS_DE_RESPOSTA,
  RESPONDER_EMAIL,
  useEmailDaConversa,
} from './useConversaDeEmail';
import { PILULA, PILULA_NOTA } from './visualEmail';

const { t } = useI18n();
// Com a caixa de resposta aberta, a barra sai: os botões estão no topo da caixa.
const email = useEmailDaConversa();

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
  // A nota privada continua a um toque, agora que a caixa só abre quando pedida.
  {
    modo: MODOS_DE_RESPOSTA.NOTA,
    chave: 'NOTA_PRIVADA',
    icone: 'i-lucide-lock',
    nota: true,
  },
];

const agir = modo => emitter.emit(RESPONDER_EMAIL, { modo });
</script>

<template>
  <li
    v-show="!email.respostaAberta.value"
    class="list-none mt-auto sticky bottom-0 z-10 w-full max-w-[960px] mx-auto grid grid-cols-2 sm:flex sm:flex-wrap gap-3 py-3 px-2 sm:ps-[68px] bg-n-surface-1 border-t border-n-weak"
    data-acoes-do-email
  >
    <button
      v-for="acao in ACOES"
      :key="acao.modo"
      type="button"
      class="justify-center sm:justify-start"
      :class="[acao.nota ? PILULA_NOTA : PILULA]"
      :data-acao-do-email="acao.modo"
      @click="agir(acao.modo)"
    >
      <Icon :icon="acao.icone" class="size-4" />
      {{ t(`CONVERSA_CANAL.EMAIL.${acao.chave}`) }}
    </button>
  </li>
</template>
