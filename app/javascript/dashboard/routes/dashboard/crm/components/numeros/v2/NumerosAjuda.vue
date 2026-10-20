<script setup>
import { computed } from 'vue';
import { P } from './numerosTextos';
import { useNumerosFormato } from './useNumerosFormato';

// "Quem precisa de ajuda" (#1992, F5 do #1871): o motivo e uma ação de ajuda,
// nunca um ranking. A IA nunca aparece aqui.
const props = defineProps({
  itens: { type: Array, required: true },
  destinoDe: { type: Function, required: true },
});

const { t } = useNumerosFormato();

const TEXTOS = { retornos: 'RETORNOS', casos_parados: 'CASOS_PARADOS' };

const linhas = computed(() =>
  props.itens.map(item => {
    const chave = TEXTOS[item.tipo];
    const params = { ...item, nome: item.pessoa.nome };
    return {
      id: `${item.tipo}-${item.pessoa.id}`,
      tipo: item.tipo,
      texto: t(`${P}.AJUDA.${chave}`, params, item.n),
      acao: t(`${P}.AJUDA.${chave}_ACAO`, params),
      destino: props.destinoDe(item.tipo, { item }),
    };
  })
);
</script>

<template>
  <section v-if="linhas.length" data-numeros-ajuda class="flex flex-col gap-2">
    <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
      {{ t(`${P}.AJUDA.TITULO`) }}
    </h3>
    <ul class="m-0 flex list-none flex-col gap-2 p-0">
      <li
        v-for="linha in linhas"
        :key="linha.id"
        :data-ajuda="linha.tipo"
        class="flex flex-col gap-1 rounded-xl bg-n-solid-1 px-4 py-3 ring-1 ring-inset ring-n-weak sm:flex-row sm:items-center sm:justify-between sm:gap-4"
      >
        <span class="text-sm text-n-slate-12">{{ linha.texto }}</span>
        <RouterLink
          v-if="linha.destino"
          :to="linha.destino.to"
          class="inline-flex min-h-11 shrink-0 items-center gap-1 text-sm font-semibold text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ linha.acao }}
          <span
            class="i-lucide-arrow-right size-3.5 rtl:rotate-180"
            aria-hidden="true"
          />
        </RouterLink>
      </li>
    </ul>
  </section>
</template>
