<script setup>
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

// #2894 — botão pequeno de copiar. `item` é o nome do que se copia ("telefone"),
// para o leitor de tela dizer "Copiar telefone".
const props = defineProps({
  valor: { type: String, required: true },
  item: { type: String, required: true },
});

const { t } = useI18n();

const copiar = async () => {
  try {
    await navigator.clipboard.writeText(props.valor);
    useAlert(t('RELACIONAMENTOS_FICHA.CABECALHO.COPIADO'));
  } catch {
    useAlert(t('RELACIONAMENTOS_FICHA.CABECALHO.NAO_COPIOU'));
  }
};
</script>

<template>
  <button
    type="button"
    data-copiar
    :aria-label="t('RELACIONAMENTOS_FICHA.CABECALHO.COPIAR', { item })"
    class="inline-flex items-center justify-center rounded-lg size-11 shrink-0 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    @click="copiar"
  >
    <span class="i-lucide-copy size-4" aria-hidden="true" />
  </button>
</template>
