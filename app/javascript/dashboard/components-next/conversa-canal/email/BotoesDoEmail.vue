<script setup>
// Botões próprios da resposta de e-mail (#1786), na barra de baixo da caixa:
// "Aa" mostra a barra de formatação fixa acima do texto; Modelos abre as respostas
// prontas; Descartar apaga o rascunho (com confirmação) e fecha a caixa.
// `parte` escolhe o grupo: "esquerda" (Aa e Modelos) ou "direita" (Descartar).
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { emitter } from 'shared/helpers/mitt';
import {
  DESCARTAR_EMAIL,
  MODELOS_DO_EMAIL,
  useEmailDaConversa,
} from './useConversaDeEmail';

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
    <button
      type="button"
      class="font-semibold text-[15px] tracking-tight"
      :class="email.formatacao.value ? '!bg-n-alpha-2' : ''"
      :aria-pressed="email.formatacao.value"
      :aria-label="t('CONVERSA_CANAL.EMAIL.FORMATACAO')"
      :title="t('CONVERSA_CANAL.EMAIL.FORMATACAO')"
      data-formatacao-do-email
      @click="email.alternarFormatacao"
    >
      <span aria-hidden="true">Aa</span>
    </button>
    <button
      type="button"
      :aria-label="t('CONVERSA_CANAL.EMAIL.MODELOS')"
      :title="t('CONVERSA_CANAL.EMAIL.MODELOS')"
      data-modelos-do-email
      @click="emitter.emit(MODELOS_DO_EMAIL)"
    >
      <Icon icon="i-lucide-file-text" class="size-[22px]" />
    </button>
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
