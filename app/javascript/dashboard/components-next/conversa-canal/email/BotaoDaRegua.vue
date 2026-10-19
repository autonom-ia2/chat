<script setup>
// "Aa" da barra de baixo do e-mail (#1786): mostra e esconde a régua de formatação
// fixa acima do texto (FORMATACAO_FIXA). Serve à resposta (BotoesDoEmail) e à gaveta
// "Escrever" (#1809). A régua vem do editor do Chatwoot com as dicas em inglês; aqui
// elas viram português (troca pelo texto exato da dica), dentro de `raiz`.
import { nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  ligada: { type: Boolean, default: false },
  // Onde está a régua (seletor CSS da caixa).
  raiz: { type: String, required: true },
});
const emit = defineEmits(['alternar']);

const { t } = useI18n();
// O símbolo do botão (o nome lido vem do aria-label traduzido).
const SIMBOLO = 'Aa';

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
    .querySelectorAll(`${props.raiz} .ProseMirror-menubar [title]`)
    .forEach(item => {
      const chave = DICAS[item.getAttribute('title')];
      if (!chave) return;
      const dica = t(`CONVERSA_CANAL.EMAIL.REGUA.${chave}`);
      item.setAttribute('title', dica);
      item.setAttribute('aria-label', dica);
    });
};
watch(
  () => props.ligada,
  ligada => ligada && traduzirDicas(),
  { immediate: true }
);
</script>

<template>
  <button
    type="button"
    class="font-semibold text-[15px] tracking-tight"
    :data-ligado="ligada || undefined"
    :aria-pressed="ligada"
    :aria-label="t('CONVERSA_CANAL.EMAIL.FORMATACAO')"
    :title="t('CONVERSA_CANAL.EMAIL.FORMATACAO')"
    data-formatacao-do-email
    @click="emit('alternar')"
  >
    <span aria-hidden="true">{{ SIMBOLO }}</span>
  </button>
</template>
