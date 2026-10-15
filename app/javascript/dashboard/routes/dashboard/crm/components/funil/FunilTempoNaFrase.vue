<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { rotuloDoTempo } from './lembretesAtender';

// #1589 — o tempo de um lembrete escolhido dentro da própria frase: poucos
// botões, um marcado. Grupo de rádio do WAI-ARIA (setas trocam e marcam; Tab
// entra só no marcado), alvo de toque de 44 px.
const props = defineProps({
  opcoes: { type: Array, required: true },
  rotulo: { type: String, required: true },
});
const horas = defineModel({ type: Number, required: true });

const { t } = useI18n();
const botoes = ref([]);
// Nenhum marcado (valor fora das opções): o primeiro recebe o Tab.
const marcado = computed(() => props.opcoes.includes(horas.value));

const marcar = indice => {
  const total = props.opcoes.length;
  const proximo = (indice + total) % total;
  horas.value = props.opcoes[proximo];
  botoes.value[proximo]?.focus();
};
const SETAS = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
const teclar = (evento, indice) => {
  const passo = SETAS[evento.key];
  if (!passo) return;
  evento.preventDefault();
  marcar(indice + passo);
};
</script>

<template>
  <span
    role="radiogroup"
    :aria-label="rotulo"
    class="my-2 grid w-full grid-cols-4 gap-1 rounded-2xl sm:flex sm:w-fit border border-n-strong bg-n-alpha-1 p-1"
    data-tempo-na-frase
  >
    <button
      v-for="(opcao, indice) in opcoes"
      :key="opcao"
      ref="botoes"
      type="button"
      role="radio"
      :aria-checked="horas === opcao"
      :tabindex="horas === opcao || (!marcado && indice === 0) ? 0 : -1"
      :data-tempo="opcao"
      class="min-h-11 whitespace-nowrap rounded-xl px-0.5 text-sm sm:px-4 sm:text-base font-semibold outline-none transition-colors focus-visible:ring-2 focus-visible:ring-n-blue-8"
      :class="
        horas === opcao
          ? 'bg-n-blue-9 text-white shadow-sm'
          : 'text-n-slate-12 hover:bg-n-alpha-3'
      "
      @click="horas = opcao"
      @keydown="teclar($event, indice)"
    >
      {{ t(rotuloDoTempo(opcao)) }}
    </button>
  </span>
</template>
