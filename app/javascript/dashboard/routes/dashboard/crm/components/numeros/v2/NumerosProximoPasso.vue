<script setup>
import { computed } from 'vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import { P, proximoPasso } from './numerosTextos';
import { useNumerosFormato } from './useNumerosFormato';

// "Próximo passo" (#1871): até 2 coisas do mês, cada uma com a ação que abre a
// lista. No máximo uma faixa amarela; o resto é a faixa neutra.
const props = defineProps({
  itens: { type: Array, required: true },
  destinoDe: { type: Function, required: true },
});

const { t } = useNumerosFormato();

const linhas = computed(() =>
  proximoPasso(props.itens).map(item => ({
    ...item,
    texto: t(`${P}.PROXIMO.${item.tipo.toUpperCase()}`, item, item.n),
    acao: t(`${P}.PROXIMO.VER`),
    destino: props.destinoDe(item.tipo, { item }),
  }))
);
</script>

<template>
  <section
    v-if="linhas.length"
    data-numeros-proximo
    class="flex flex-col gap-2"
  >
    <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
      {{ t(`${P}.PROXIMO.TITULO`) }}
    </h3>
    <Banner
      v-for="linha in linhas"
      :key="linha.tipo"
      :color="linha.aviso ? 'amber' : 'slate'"
      :data-proximo="linha.tipo"
    >
      <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
        <span class="text-sm">{{ linha.texto }}</span>
        <RouterLink
          v-if="linha.destino"
          :to="linha.destino.to"
          class="link inline-flex min-h-11 items-center gap-1 text-sm font-semibold underline underline-offset-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ linha.acao }}
          <span
            class="i-lucide-arrow-right size-3.5 rtl:rotate-180"
            aria-hidden="true"
          />
        </RouterLink>
      </div>
    </Banner>
  </section>
</template>
