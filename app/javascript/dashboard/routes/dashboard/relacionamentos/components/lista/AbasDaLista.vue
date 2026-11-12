<script setup>
import { nextTick, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { ABAS } from '../../fonte/grupos';
import { PAINEL_DAS_ABAS, idDaAba } from '../../lista/idsDasAbas';

// #2894 — Pessoas · Empresas. Abas de verdade (role="tablist"): setas, Home e
// End trocam de aba e levam o foco junto; só a aba escolhida entra na ordem do
// Tab. A escolha mora na URL (quem usa liga o v-model à rota).
const props = defineProps({
  modelValue: { type: String, required: true },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const ABAS_NA_ORDEM = [ABAS.PESSOAS, ABAS.EMPRESAS];
const NOMES = {
  [ABAS.PESSOAS]: 'RELACIONAMENTOS.LISTA.ABAS.PESSOAS',
  [ABAS.EMPRESAS]: 'RELACIONAMENTOS.LISTA.ABAS.EMPRESAS',
};
const lista = useTemplateRef('lista');

const escolher = async indice => {
  const aba = ABAS_NA_ORDEM[indice];
  emit('update:modelValue', aba);
  await nextTick();
  lista.value?.querySelector(`#${idDaAba(aba)}`)?.focus();
};

const aoTeclar = evento => {
  const atual = ABAS_NA_ORDEM.indexOf(props.modelValue);
  const ultimo = ABAS_NA_ORDEM.length - 1;
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
      v-for="aba in ABAS_NA_ORDEM"
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
