<script setup>
import { useId } from 'vue';

// #3168 — uma escolha entre poucas opções lado a lado, num grupo de rádio
// (setas trocam, como o padrão do WAI-ARIA), cada opção com 44 px de alvo. A
// escolhida fica branca, na cor da marca. Nasceu da chave "Ver os grupos por"
// (#3097, ChaveDosGrupos) e serve também a "Mostrar quem tem" e ao "Sim | Não"
// da gaveta "Mais filtros".
//   opcoes: [{ value, label }]    v-model: o value escolhido
const props = defineProps({
  modelValue: { type: [String, Boolean], required: true },
  opcoes: { type: Array, required: true },
  rotulo: { type: String, required: true },
  // O rótulo só para o leitor de tela (quando o campo já tem um visível acima).
  rotuloEscondido: { type: Boolean, default: false },
  marca: { type: String, default: undefined },
});
const emit = defineEmits(['update:modelValue']);

const idDoRotulo = useId();
const PASSOS = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };

const escolher = valor => {
  if (valor !== props.modelValue) emit('update:modelValue', valor);
};
const aoTeclar = (evento, indice) => {
  const passo = PASSOS[evento.key];
  if (!passo) return;
  evento.preventDefault();
  const total = props.opcoes.length;
  const proxima = props.opcoes[(indice + passo + total) % total];
  escolher(proxima.value);
  evento.currentTarget.parentElement
    .querySelector(`[data-opcao="${String(proxima.value)}"]`)
    ?.focus();
};
</script>

<template>
  <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
    <span
      :id="idDoRotulo"
      class="text-sm text-n-slate-11"
      :class="{ 'sr-only': rotuloEscondido }"
    >
      {{ rotulo }}
    </span>
    <div
      role="radiogroup"
      :aria-labelledby="idDoRotulo"
      :data-relacionamentos="marca"
      class="inline-flex max-w-full p-0.5 rounded-lg bg-n-alpha-2"
    >
      <button
        v-for="(opcao, indice) in opcoes"
        :key="String(opcao.value)"
        type="button"
        role="radio"
        :data-opcao="String(opcao.value)"
        :aria-checked="modelValue === opcao.value"
        :tabindex="modelValue === opcao.value ? 0 : -1"
        class="relative px-3 text-sm font-medium transition-colors rounded-md min-h-9 before:absolute before:inset-x-0 before:-inset-y-1 before:content-[''] focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          modelValue === opcao.value
            ? 'bg-n-solid-1 text-n-brand font-semibold shadow-sm ring-1 ring-n-weak'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="escolher(opcao.value)"
        @keydown="aoTeclar($event, indice)"
      >
        {{ opcao.label }}
      </button>
    </div>
  </div>
</template>
