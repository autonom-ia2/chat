<script setup>
import { computed, nextTick, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { ABAS } from '../../fonte/grupos';
import { ABA_SEGUROS } from '../../fonte/gruposDeSeguros';
import { PAINEL_DAS_ABAS, idDaAba } from '../../lista/idsDasAbas';

// #2894 — Pessoas · Empresas. Abas de verdade (role="tablist"): setas, Home e
// End trocam de aba e levam o foco junto; só a aba escolhida entra na ordem do
// Tab. A escolha mora na URL (quem usa liga o v-model à rota).
// #2897 — com `comSeguros` (conta que tem a carteira de seguros), mais uma aba:
// Seguros. Conta sem Empresas (`comEmpresas` falso) fica com Pessoas · Seguros.
// #3057 — redesenho: abas sublinhadas, como as da lista de conversas
// (components-next/Conversation/ListaDeConversas/ListaAbas.vue), sobre uma linha
// fina. A escolhida tem o texto forte e o traço da marca embaixo. Antes era um
// grupo cinza que, dentro da coluna da página, esticava na largura toda.
const props = defineProps({
  modelValue: { type: String, required: true },
  comEmpresas: { type: Boolean, default: true },
  comSeguros: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const abasNaOrdem = computed(() => [
  ABAS.PESSOAS,
  ...(props.comEmpresas ? [ABAS.EMPRESAS] : []),
  ...(props.comSeguros ? [ABA_SEGUROS] : []),
]);
const NOMES = {
  [ABAS.PESSOAS]: 'RELACIONAMENTOS.LISTA.ABAS.PESSOAS',
  [ABAS.EMPRESAS]: 'RELACIONAMENTOS.LISTA.ABAS.EMPRESAS',
  [ABA_SEGUROS]: 'RELACIONAMENTOS_CARTEIRA.ABA',
};
const lista = useTemplateRef('lista');

const escolher = async indice => {
  const aba = abasNaOrdem.value[indice];
  emit('update:modelValue', aba);
  await nextTick();
  lista.value?.querySelector(`#${idDaAba(aba)}`)?.focus();
};

const aoTeclar = evento => {
  const atual = abasNaOrdem.value.indexOf(props.modelValue);
  const ultimo = abasNaOrdem.value.length - 1;
  const destinos = {
    ArrowRight: atual === ultimo ? 0 : atual + 1,
    ArrowLeft: atual === 0 ? ultimo : atual - 1,
    Home: 0,
    End: ultimo,
  };
  if (!(evento.key in destinos)) return;
  evento.preventDefault();
  escolher(destinos[evento.key]);
};
</script>

<template>
  <div
    ref="lista"
    role="tablist"
    :aria-label="t('RELACIONAMENTOS.LISTA.ABAS.ROTULO')"
    data-relacionamentos="abas"
    class="flex items-end gap-6 overflow-x-auto border-b border-n-weak"
    @keydown="aoTeclar"
  >
    <button
      v-for="aba in abasNaOrdem"
      :id="idDaAba(aba)"
      :key="aba"
      type="button"
      role="tab"
      :data-relacionamentos="`aba-${aba}`"
      :aria-selected="modelValue === aba ? 'true' : 'false'"
      :aria-controls="PAINEL_DAS_ABAS"
      :tabindex="modelValue === aba ? 0 : -1"
      class="relative px-0.5 text-base bg-transparent border-0 rounded-t-md whitespace-nowrap min-h-12 transition-colors after:absolute after:inset-x-0 after:bottom-0 after:h-0.5 after:rounded-full focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand"
      :class="
        modelValue === aba
          ? 'font-semibold text-n-slate-12 after:bg-n-brand'
          : 'font-medium text-n-slate-11 hover:text-n-slate-12 after:bg-transparent hover:after:bg-n-slate-6'
      "
      @click="emit('update:modelValue', aba)"
    >
      {{ t(NOMES[aba]) }}
    </button>
  </div>
</template>
