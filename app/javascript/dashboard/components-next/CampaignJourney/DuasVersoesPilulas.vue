<script setup>
// #3099 — uma escolha da regra das duas versões (o que conta como melhor, a espera, a divisão) em pílulas: grupo de
// rádio do WAI-ARIA, como SentenceChoice (setas trocam e marcam, pulando a opção apagada; Tab entra só na marcada).
// A marcada não depende só da cor: leva o ícone de certo e o contorno mais grosso.
import { computed, ref } from 'vue';

const props = defineProps({
  // [{ valor, rotulo, detalhe?, serve? }] — `serve: false` deixa a opção apagada.
  opcoes: { type: Array, required: true },
  // O id do texto que dá nome ao grupo (a pergunta).
  rotuladoPor: { type: String, required: true },
  modelValue: { type: [String, Number], default: null },
  // O atributo data-* de cada pílula, para os specs e os prints (data-criterio, data-espera, data-divisao).
  marca: { type: String, required: true },
});
const emit = defineEmits(['update:modelValue']);

const botoes = ref([]);
const marcaDa = opcao => ({ [`data-${props.marca}`]: opcao.valor });
const serve = opcao => opcao.serve !== false;
const temMarcada = computed(() =>
  props.opcoes.some(opcao => opcao.valor === props.modelValue && serve(opcao))
);
const recebeTab = (opcao, indice) =>
  temMarcada.value
    ? opcao.valor === props.modelValue
    : indice === props.opcoes.findIndex(serve);

const SETAS = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
const andar = (evento, indice) => {
  const passo = SETAS[evento.key];
  if (!passo) return;
  evento.preventDefault();
  const total = props.opcoes.length;
  let proximo = indice;
  for (let volta = 0; volta < total; volta += 1) {
    proximo = (proximo + passo + total) % total;
    if (serve(props.opcoes[proximo])) break;
  }
  emit('update:modelValue', props.opcoes[proximo].valor);
  botoes.value[proximo]?.focus();
};

// Foco de quem abre o "Alterar": a pílula que recebe o Tab.
const focar = () => botoes.value[props.opcoes.findIndex(recebeTab)]?.focus();
defineExpose({ focar });

const PILULA =
  'flex min-h-11 items-center gap-2 rounded-xl px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:cursor-not-allowed disabled:text-n-slate-10';
// Contorno por anel (ring): a regra base de `button` em _base.scss zera a borda e venceria o `border`.
const classeDa = marcada =>
  marcada
    ? 'ring-2 ring-inset ring-n-blue-9 bg-n-blue-2 text-n-blue-11'
    : 'ring-1 ring-inset ring-n-slate-7 bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-1';
</script>

<template>
  <div
    class="flex flex-wrap gap-2"
    role="radiogroup"
    :aria-labelledby="rotuladoPor"
  >
    <button
      v-for="(opcao, indice) in opcoes"
      :key="opcao.valor"
      ref="botoes"
      type="button"
      role="radio"
      :aria-checked="modelValue === opcao.valor"
      :tabindex="recebeTab(opcao, indice) ? 0 : -1"
      :disabled="!serve(opcao)"
      v-bind="marcaDa(opcao)"
      :class="[PILULA, classeDa(modelValue === opcao.valor)]"
      @click="emit('update:modelValue', opcao.valor)"
      @keydown="andar($event, indice)"
    >
      <span
        v-if="modelValue === opcao.valor"
        class="i-lucide-check size-4 shrink-0"
        aria-hidden="true"
        data-marcada
      />
      <span v-if="opcao.detalhe" class="flex flex-col items-start py-1">
        <span>{{ opcao.rotulo }}</span>
        <span class="text-xs font-normal tabular-nums text-n-slate-11">
          {{ opcao.detalhe }}
        </span>
      </span>
      <span v-else class="tabular-nums">{{ opcao.rotulo }}</span>
    </button>
  </div>
</template>
