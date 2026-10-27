<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../composables/useFormatoDoPainel';
import Segmento from './comum/Segmento.vue';

// #2226 v2 (§1) — a barra fixa embaixo da faixa: abas Resumo | Detalhe, o período (7, 30, 90 dias ou
// tudo), a base do período e o selo "Conferimos N procuras", que leva até "Quanto confiar". No
// celular a barra fica só com o período (as abas descem para o conteúdo, na página) e a base some.
const props = defineProps({
  periodos: { type: Array, required: true },
  base: { type: Object, default: null },
  conferidas: { type: Number, default: 0 },
});

const emit = defineEmits(['confianca']);

const aba = defineModel('aba', { type: String, required: true });
const periodo = defineModel('periodo', { type: String, required: true });

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.BARRA';

const abas = computed(() => [
  { value: 'resumo', label: fmt.t(`${NS}.ABA.RESUMO`) },
  { value: 'detalhe', label: fmt.t(`${NS}.ABA.DETALHE`) },
]);
const opcoesDePeriodo = computed(() =>
  props.periodos.map(chave => ({
    value: chave,
    label: fmt.t(`${NS}.PERIODO.${chave.toUpperCase()}`),
  }))
);
</script>

<template>
  <div
    data-barra
    class="sticky top-0 z-10 w-full px-4 py-2 border-b md:px-6 bg-n-background/95 backdrop-blur border-n-weak"
  >
    <div
      class="flex flex-wrap items-center w-full gap-x-4 gap-y-2 mx-auto max-w-screen-2xl"
    >
      <div class="hidden md:block">
        <Segmento
          v-model="aba"
          data-abas
          :opcoes="abas"
          :rotulo="fmt.t(`${NS}.ABAS`)"
        />
      </div>
      <Segmento
        v-model="periodo"
        data-periodos
        :opcoes="opcoesDePeriodo"
        :rotulo="fmt.t(`${NS}.PERIODOS`)"
      />
      <div
        class="items-center hidden ms-auto md:flex gap-x-3 text-xs text-n-slate-11 tabular-nums"
      >
        <span v-if="base" data-base>
          {{
            fmt.t(`${NS}.BASE`, {
              procuras: fmt.n(base.procuras),
              conversas: fmt.n(base.conversas),
            })
          }}
        </span>
        <button
          v-if="conferidas"
          type="button"
          data-selo-confianca
          class="inline-flex items-center gap-1 px-2.5 font-semibold rounded-full min-h-11 text-n-teal-11 hover:underline underline-offset-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          @click="emit('confianca')"
        >
          <span class="i-lucide-badge-check size-4" aria-hidden="true" />
          {{ fmt.t(`${NS}.CONFERIMOS`, { n: fmt.n(conferidas) }) }}
          <span
            class="i-lucide-chevron-right size-3.5 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
      </div>
    </div>
  </div>
</template>
