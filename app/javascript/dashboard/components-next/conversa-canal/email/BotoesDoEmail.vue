<script setup>
// Botões próprios da resposta de e-mail (#1786), na barra de baixo da caixa:
// "Aa" mostra a barra de formatação fixa acima do texto; Modelos abre as respostas
// prontas (lista com busca, sem escrever "/" no texto); Descartar apaga o rascunho
// (com confirmação) e fecha a caixa. Um fio separa os nossos dos botões do Chatwoot.
// `parte` escolhe o grupo: "esquerda" (Aa e Modelos) ou "direita" (Descartar).
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { emitter } from 'shared/helpers/mitt';
import ModelosDoEmail from './ModelosDoEmail.vue';
import BotaoDaRegua from './BotaoDaRegua.vue';
import { DESCARTAR_EMAIL, useEmailDaConversa } from './useConversaDeEmail';

defineProps({
  parte: {
    type: String,
    required: true,
    validator: v => ['esquerda', 'direita'].includes(v),
  },
});

const { t } = useI18n();
const email = useEmailDaConversa();
const confirmando = ref(false);

const descartar = () => {
  if (!confirmando.value) {
    confirmando.value = true;
    return;
  }
  confirmando.value = false;
  emitter.emit(DESCARTAR_EMAIL);
};
</script>

<template>
  <template v-if="parte === 'esquerda'">
    <BotaoDaRegua
      :ligada="email.formatacao.value"
      raiz=".reply-box"
      @alternar="email.alternarFormatacao"
    />
    <ModelosDoEmail />
    <span
      class="w-px h-6 mx-1.5 bg-n-weak flex-shrink-0"
      aria-hidden="true"
      data-separador-da-barra
    />
  </template>
  <button
    v-else
    type="button"
    class="inline-flex items-center gap-1.5 h-10 rounded-full text-sm"
    :class="
      confirmando
        ? 'px-4 bg-n-ruby-3 text-n-ruby-11 hover:bg-n-ruby-4'
        : 'w-10 justify-center text-n-slate-11 hover:bg-n-alpha-2'
    "
    :aria-label="
      confirmando
        ? t('CONVERSA_CANAL.EMAIL.CONFIRMAR_DESCARTE')
        : t('CONVERSA_CANAL.EMAIL.DESCARTAR')
    "
    :title="t('CONVERSA_CANAL.EMAIL.DESCARTAR')"
    data-descartar-email
    @click="descartar"
    @blur="confirmando = false"
  >
    <Icon icon="i-lucide-trash-2" class="size-[20px]" />
    <span v-if="confirmando">
      {{ t('CONVERSA_CANAL.EMAIL.CONFIRMAR_DESCARTE') }}
    </span>
  </button>
</template>
