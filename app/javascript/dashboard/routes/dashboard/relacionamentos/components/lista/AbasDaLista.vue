<script setup>
import { computed, nextTick, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { ABAS } from '../../fonte/grupos';
import { ABA_SEGUROS } from '../../fonte/gruposDeSeguros';
import { PAINEL_DAS_ABAS, idDaAba } from '../../lista/idsDasAbas';

// #2894 — Pessoas · Empresas. Abas de verdade (role="tablist"): setas, Home e
// End trocam de aba e levam o foco junto; só a aba escolhida entra na ordem do
// Tab. A escolha mora na URL (quem usa liga o v-model à rota).
// #2897 — com `comSeguros` (conta de seguros), a terceira aba: Seguros.
const props = defineProps({
  modelValue: { type: String, required: true },
  comSeguros: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const abasNaOrdem = computed(() => [
  ABAS.PESSOAS,
  ABAS.EMPRESAS,
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
    class="inline-flex gap-1 p-1 rounded-xl bg-n-alpha-1"
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
      class="px-5 text-sm font-medium transition-colors rounded-lg min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :class="
        modelValue === aba
          ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
      @click="emit('update:modelValue', aba)"
    >
      {{ t(NOMES[aba]) }}
    </button>
  </div>
</template>
