<script setup>
import { computed } from 'vue';
import { P } from './numerosTextos';
import { useNumerosFormato } from './useNumerosFormato';

// "Quem precisa de ajuda" (#1992, F5 do #1871): uma linha por pessoa, com o
// motivo e uma ação de ajuda, nunca um ranking. Os retornos atrasados e os
// casos parados ficam na mesma linha, e cada número abre a fila daquela
// pessoa. A IA nunca aparece aqui. Sem ninguém na lista, quem chama não monta
// o bloco.
const props = defineProps({
  itens: { type: Array, required: true },
  destinoDe: { type: Function, required: true },
});

const { t } = useNumerosFormato();

const MOTIVOS = [
  { tipo: 'retornos', campo: 'retornos', chave: 'RETORNOS' },
  { tipo: 'casos_parados', campo: 'casosParados', chave: 'CASOS_PARADOS' },
];

const motivosDe = item =>
  MOTIVOS.filter(motivo => item[motivo.campo] > 0).map(motivo => {
    const n = item[motivo.campo];
    const nome = item.pessoa.nome;
    return {
      tipo: motivo.tipo,
      texto: t(`${P}.AJUDA.${motivo.chave}_N`, { n }, n),
      rotulo: t(`${P}.AJUDA.${motivo.chave}_ACAO`, { nome }),
      destino: props.destinoDe(motivo.tipo, { item }),
    };
  });

const linhas = computed(() =>
  props.itens.map(item => ({
    id: item.pessoa.id,
    nome: item.pessoa.nome,
    motivos: motivosDe(item),
  }))
);
</script>

<template>
  <section data-numeros-ajuda class="flex flex-col gap-2">
    <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
      {{ t(`${P}.AJUDA.TITULO`) }}
    </h3>
    <ul class="m-0 flex list-none flex-col gap-2 p-0">
      <li
        v-for="linha in linhas"
        :key="linha.id"
        :data-ajuda-pessoa="linha.id"
        class="flex flex-col gap-1 rounded-xl bg-n-solid-1 px-4 py-3 ring-1 ring-inset ring-n-weak sm:flex-row sm:flex-wrap sm:items-center sm:gap-x-3"
      >
        <span class="text-sm font-semibold text-n-slate-12">
          {{ linha.nome }}
        </span>
        <template v-for="motivo in linha.motivos" :key="motivo.tipo">
          <RouterLink
            v-if="motivo.destino"
            :to="motivo.destino.to"
            :data-ajuda="motivo.tipo"
            :aria-label="motivo.rotulo"
            class="inline-flex min-h-11 w-fit items-center gap-1 text-sm font-semibold text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          >
            {{ motivo.texto }}
            <span
              class="i-lucide-arrow-right size-3.5 rtl:rotate-180"
              aria-hidden="true"
            />
          </RouterLink>
          <span
            v-else
            :data-ajuda="motivo.tipo"
            class="inline-flex min-h-11 items-center text-sm text-n-slate-12"
          >
            {{ motivo.texto }}
          </span>
        </template>
      </li>
    </ul>
  </section>
</template>
