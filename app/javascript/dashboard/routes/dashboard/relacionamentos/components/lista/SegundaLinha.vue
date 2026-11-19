<script setup>
import { computed } from 'vue';
import { SEPARADOR } from '../comum/ponto';

// #2894 — a segunda linha de uma pessoa ou empresa. Cada informação é um bloco:
// no celular uma por linha, sem "·" (que ficaria pendurado no fim da linha);
// de `sm` para cima ficam todas na mesma linha, separadas por "·".
// #3057 (revisão) — no celular a linha não vira uma pilha de 3 ou 4 linhas:
// as informações curtas ficam juntas numa linha, separadas por "·", e a que
// vem com `sozinha` desce para uma linha própria, a última, cortada com "…"
// se não couber (a empresa da pessoa, a data do seguro). Cada parte é um texto
// ou { texto, sozinha }. De `sm` para cima nada muda.
const props = defineProps({
  partes: { type: Array, required: true },
});

const itens = computed(() =>
  props.partes.map(parte =>
    typeof parte === 'string' ? { texto: parte, sozinha: false } : parte
  )
);
// O "·" antes de uma parte aparece no celular só entre duas partes que ficam
// juntas na mesma linha.
const separadorNoCelular = indice =>
  !itens.value[indice].sozinha &&
  itens.value.slice(0, indice).some(parte => !parte.sozinha);
</script>

<template>
  <p
    data-segunda-linha
    class="min-w-0 m-0 text-sm text-n-slate-11 max-sm:flex max-sm:flex-wrap sm:break-words"
  >
    <template v-for="(parte, indice) in itens" :key="indice">
      <span
        v-if="indice > 0"
        :class="
          separadorNoCelular(indice) ? 'whitespace-pre' : 'hidden sm:inline'
        "
        >{{ SEPARADOR }}</span
      >
      <span
        :class="
          parte.sozinha
            ? 'max-sm:order-last max-sm:basis-full max-sm:truncate'
            : 'max-sm:whitespace-nowrap'
        "
        >{{ parte.texto }}</span
      >
    </template>
  </p>
</template>
