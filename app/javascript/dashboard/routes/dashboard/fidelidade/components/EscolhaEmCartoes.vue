<script setup>
import { useId } from 'vue';

// #3100 — escolha de um entre poucos (2 ou 3) em cartões grandes, com
// <input type="radio"> de verdade: setas, Tab e leitor de tela vêm do
// navegador. Mesma anatomia do CheckCard da casa (borda e fundo azuis no
// escolhido), com a bolinha no lugar do visto. Cada opção:
// { value, titulo, dica, icone }.
defineProps({
  legenda: { type: String, required: true },
  opcoes: { type: Array, required: true },
});

const escolhido = defineModel({ type: [String, Number], default: null });
const nome = useId();
</script>

<template>
  <fieldset class="flex flex-col gap-2 p-0 m-0 border-0">
    <legend class="mb-2 text-heading-3 text-n-slate-12">{{ legenda }}</legend>
    <div
      class="grid gap-3"
      :class="opcoes.length === 3 ? 'sm:grid-cols-3' : 'sm:grid-cols-2'"
    >
      <label
        v-for="opcao in opcoes"
        :key="opcao.value"
        :data-escolha="opcao.value"
        class="relative flex gap-3 p-4 transition-colors border cursor-pointer min-h-11 rounded-2xl bg-n-solid-1 has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-n-brand"
        :class="
          escolhido === opcao.value
            ? 'border-n-blue-8 bg-n-blue-2 shadow-sm'
            : 'border-n-weak hover:border-n-slate-7'
        "
      >
        <input
          v-model="escolhido"
          type="radio"
          class="sr-only"
          :name="nome"
          :value="opcao.value"
        />
        <span
          class="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full"
          :class="
            escolhido === opcao.value
              ? 'bg-n-blue-9'
              : 'ring-2 ring-inset ring-n-slate-7'
          "
          aria-hidden="true"
        >
          <span
            v-if="escolhido === opcao.value"
            class="bg-white rounded-full size-2"
          />
        </span>
        <span class="flex flex-col flex-1 min-w-0 gap-1">
          <span
            class="flex items-center gap-2 text-[0.9375rem] font-semibold leading-snug text-n-slate-12"
          >
            <span
              v-if="opcao.icone"
              :class="opcao.icone"
              class="size-4 shrink-0 text-n-slate-11"
              aria-hidden="true"
            />
            {{ opcao.titulo }}
          </span>
          <span v-if="opcao.dica" class="text-sm text-n-slate-11">
            {{ opcao.dica }}
          </span>
        </span>
      </label>
    </div>
  </fieldset>
</template>
