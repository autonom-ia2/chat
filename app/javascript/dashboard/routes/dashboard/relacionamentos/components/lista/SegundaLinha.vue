<script setup>
import { computed } from 'vue';
import { SEPARADOR } from '../comum/ponto';

// #2894 — a segunda linha de uma pessoa ou empresa. Cada informação é um bloco:
// no celular uma por linha, sem "·" (que ficaria pendurado no fim da linha);
// de `sm` para cima ficam todas na mesma linha, separadas por "·".
// #3057 (revisão) — no celular a linha não vira uma pilha de 3 ou 4 linhas.
// Cada parte é um texto ou { texto, sozinha, corta }:
// - `sozinha` fica numa linha própria, no lugar em que vem (o telefone da
//   pessoa, a data do seguro), cortada com "…" se não couber;
// - as outras ficam juntas na mesma linha, separadas por "·", e a que tem
//   `corta` ocupa o resto dessa linha, cortada com "…" (a empresa).
// O "·" só aparece no celular entre duas partes da mesma linha: nunca fica
// pendurado no fim de uma linha. De `sm` para cima nada muda.
// #3078 (revisão) — quando a parte seguinte é comum (nem `sozinha` nem
// `corta`), o "·" vai dentro dela, e a linha quebra antes do "·", não depois
// (a linha da empresa: "4 pessoas · Campinas · Falou há 2 dias").
const props = defineProps({
  partes: { type: Array, required: true },
});

const itens = computed(() =>
  props.partes.map(parte =>
    typeof parte === 'string' ? { texto: parte } : parte
  )
);
const separadorNoCelular = indice =>
  !itens.value[indice].sozinha && !itens.value[indice - 1].sozinha;
const separadorJunto = indice =>
  indice > 0 &&
  separadorNoCelular(indice) &&
  !itens.value[indice].sozinha &&
  !itens.value[indice].corta;
const separadorSolto = indice => indice > 0 && !separadorJunto(indice);
const classeDoSeparador = indice =>
  separadorNoCelular(indice) ? 'whitespace-pre' : 'hidden sm:inline';
// A parte comum não quebra no celular; com o "·" dentro, guarda os espaços
// dele (sem `pre` o espaço do começo some).
const classe = (parte, indice) => {
  if (parte.sozinha) return 'max-sm:basis-full max-sm:truncate';
  if (parte.corta)
    return 'max-sm:min-w-0 max-sm:flex-1 max-sm:basis-0 max-sm:truncate';
  return separadorJunto(indice)
    ? 'max-sm:whitespace-pre'
    : 'max-sm:whitespace-nowrap';
};
const texto = (parte, indice) =>
  separadorJunto(indice) ? `${SEPARADOR}${parte.texto}` : parte.texto;
</script>

<template>
  <p
    data-segunda-linha
    class="min-w-0 m-0 text-sm text-n-slate-11 max-sm:flex max-sm:flex-wrap sm:break-words"
  >
    <template v-for="(parte, indice) in itens" :key="indice">
      <template v-if="separadorSolto(indice)">
        <span :class="classeDoSeparador(indice)">{{ SEPARADOR }}</span>
      </template>
      <span :class="classe(parte, indice)">{{ texto(parte, indice) }}</span>
    </template>
  </p>
</template>
