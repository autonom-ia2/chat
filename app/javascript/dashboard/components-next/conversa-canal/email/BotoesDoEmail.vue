<script setup>
// Botões próprios da resposta de e-mail (#1786), na barra de baixo da caixa:
// "Aa" mostra a barra de formatação fixa acima do texto; Modelos abre as respostas
// prontas (lista com busca, sem escrever "/" no texto); Descartar apaga o rascunho
// (com confirmação) e fecha a caixa. Um fio separa os nossos dos botões do Chatwoot.
// `parte` escolhe o grupo: "esquerda" (Aa e Modelos) ou "direita" (Descartar).
import { nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { emitter } from 'shared/helpers/mitt';
import ModelosDoEmail from './ModelosDoEmail.vue';
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

// A régua de formatação vem do editor do Chatwoot com as dicas em inglês; no e-mail
// novo elas viram português (troca pelo texto exato da dica).
const DICAS = {
  Copilot: 'ESCREVER_COM_IA',
  'Toggle strong style': 'NEGRITO',
  'Toggle emphasis': 'ITALICO',
  'Toggle code font': 'CODIGO',
  'Add or remove link': 'LINK',
  'Wrap in bullet list': 'LISTA',
  'Wrap in ordered list': 'LISTA_NUMERADA',
  'Upload image': 'IMAGEM_NO_TEXTO',
  'Undo last change': 'DESFAZER',
  'Redo last undone change': 'REFAZER',
};
const traduzirDicas = async () => {
  await nextTick();
  document
    .querySelectorAll('.reply-box .ProseMirror-menubar [title]')
    .forEach(item => {
      const chave = DICAS[item.getAttribute('title')];
      if (!chave) return;
      const dica = t(`CONVERSA_CANAL.EMAIL.REGUA.${chave}`);
      item.setAttribute('title', dica);
      item.setAttribute('aria-label', dica);
    });
};
watch(
  () => email.formatacao.value,
  ligada => ligada && traduzirDicas(),
  { immediate: true }
);

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
      :data-ligado="email.formatacao.value || undefined"
      :aria-pressed="email.formatacao.value"
      :aria-label="t('CONVERSA_CANAL.EMAIL.FORMATACAO')"
      :title="t('CONVERSA_CANAL.EMAIL.FORMATACAO')"
      data-formatacao-do-email
      @click="email.alternarFormatacao"
    >
      <span aria-hidden="true">Aa</span>
    </button>
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
