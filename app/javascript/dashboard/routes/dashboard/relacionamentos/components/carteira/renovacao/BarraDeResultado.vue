<script setup>
import { computed } from 'vue';
import { porcentagem } from '../../../carteira/resultados';
import { larguraDaBarra } from '../../../trazer/larguraDaBarra';

// #2898 — uma linha dos resultados: o nome, a barra e o número escrito. A
// barra é só desenho (o número ao lado diz o mesmo para o leitor de tela), com
// a largura em classe, como a barra de andamento de trazer. No celular a barra
// desce para baixo do nome.
const props = defineProps({
  nome: { type: String, required: true },
  // O que vai escrito ao lado ("2", "7 de 9 renovaram").
  valor: { type: String, required: true },
  parte: { type: Number, required: true },
  total: { type: Number, required: true },
});

const largura = computed(() => porcentagem(props.parte, props.total));
</script>

<template>
  <li
    data-carteira="barra-de-resultado"
    class="grid items-center grid-cols-2 py-3 gap-x-4 gap-y-2 md:grid-cols-[minmax(0,14rem)_minmax(0,1fr)_auto]"
  >
    <span class="text-base break-words text-n-slate-12">{{ nome }}</span>
    <span
      class="text-base text-end tabular-nums text-n-slate-11 md:order-3 md:min-w-40"
    >
      {{ valor }}
    </span>
    <span
      aria-hidden="true"
      class="h-2 col-span-2 overflow-hidden rounded-full bg-n-alpha-2 md:col-span-1 md:order-2"
    >
      <span
        class="block h-full rounded-full bg-n-blue-11 dark:bg-n-blue-9"
        :class="larguraDaBarra(largura)"
        :data-largura="largura"
      />
    </span>
  </li>
</template>
