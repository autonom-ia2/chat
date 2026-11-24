<script setup>
import { nextTick, useTemplateRef } from 'vue';
import { F, useTextosDaFidelidade } from '../useTextosDaFidelidade';
import {
  ABAS_DA_FIDELIDADE,
  PAINEL_DA_FIDELIDADE,
  idDaAbaDaFidelidade,
} from '../abas';

// #3100 — Cartão fidelidade · Cupons. Abas de verdade (role="tablist"), com o
// mesmo desenho e o mesmo teclado das abas de Relacionamentos (AbasDaLista):
// setas, Home e End trocam de aba e levam o foco junto. A escolha mora na URL
// (quem usa liga o v-model à rota, ?aba=cupons).

defineProps({
  modelValue: { type: String, required: true },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useTextosDaFidelidade();
const lista = useTemplateRef('lista');

const escolher = async indice => {
  const aba = ABAS_DA_FIDELIDADE[indice];
  emit('update:modelValue', aba);
  await nextTick();
  lista.value?.querySelector(`#${idDaAbaDaFidelidade(aba)}`)?.focus();
};

const aoTeclar = (evento, atual) => {
  const ultimo = ABAS_DA_FIDELIDADE.length - 1;
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
    :aria-label="t(`${F}.ABAS.ROTULO`)"
    data-fidelidade="abas"
    class="flex items-end gap-6 overflow-x-auto border-b border-n-weak"
  >
    <button
      v-for="(aba, indice) in ABAS_DA_FIDELIDADE"
      :id="idDaAbaDaFidelidade(aba)"
      :key="aba"
      type="button"
      role="tab"
      :data-fidelidade="`aba-${aba}`"
      :aria-selected="modelValue === aba ? 'true' : 'false'"
      :aria-controls="PAINEL_DA_FIDELIDADE"
      :tabindex="modelValue === aba ? 0 : -1"
      class="relative px-0.5 text-base bg-transparent border-0 rounded-t-md whitespace-nowrap min-h-12 transition-colors after:absolute after:inset-x-0 after:bottom-0 after:h-0.5 after:rounded-full focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand"
      :class="
        modelValue === aba
          ? 'font-semibold text-n-slate-12 after:bg-n-brand'
          : 'font-medium text-n-slate-11 hover:text-n-slate-12 after:bg-transparent hover:after:bg-n-slate-6'
      "
      @click="emit('update:modelValue', aba)"
      @keydown="evento => aoTeclar(evento, indice)"
    >
      {{ t(`${F}.ABAS.${aba.toUpperCase()}`) }}
    </button>
  </div>
</template>
