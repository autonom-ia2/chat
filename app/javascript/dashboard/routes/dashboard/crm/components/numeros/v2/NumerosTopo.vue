<script setup>
import { computed } from 'vue';
import { P, pctDe } from './numerosTextos';
import {
  botaoDoTopoDe,
  fraseDoTopoDe,
  tituloDoTopoDe,
} from './numerosTextosEquipe';
import { useNumerosFormato } from './useNumerosFormato';
import { inicioDe, larguraDe } from './barras';

// Topo de CRM › Números (#1871): rótulo do mês, título com um número, uma
// frase, uma barra com a marca de "onde deveria estar hoje" (só com meta, F4)
// e um botão que abre uma lista.
const props = defineProps({
  topo: { type: Object, required: true },
  mes: { type: Object, required: true },
  mesNome: { type: String, required: true },
  rotuloDoMes: { type: String, required: true },
  moeda: { type: String, default: 'BRL' },
  destino: { type: Object, default: null },
  // #1991: quem define as metas ganha o atalho para a gaveta (só no mês de hoje).
  podeDefinirMetas: { type: Boolean, default: false },
});
const emit = defineEmits(['metas']);

const { t, traduzir } = useNumerosFormato(props.moeda);

const venda = computed(() => props.topo.medida === 'valor');
const titulo = computed(() => {
  const texto = tituloDoTopoDe(props.topo, props.mes);
  return traduzir(
    { ...texto, params: { ...texto.params, mes: props.mesNome } },
    ['valor']
  );
});
const frase = computed(() =>
  traduzir(
    fraseDoTopoDe(props.topo, props.mes),
    venda.value ? ['feito', 'meta', 'valor'] : []
  )
);
const pct = computed(() => pctDe(props.topo.feito, props.topo.meta));
const esperado = computed(() =>
  props.mes.fechado ? 100 : props.topo.esperadoPct
);
const botao = computed(() =>
  props.topo.botao ? traduzir(botaoDoTopoDe(props.topo.botao), ['valor']) : ''
);
</script>

<template>
  <section
    data-numeros-topo
    class="relative flex flex-col gap-3 overflow-hidden rounded-2xl bg-n-heroi px-5 py-5 text-white ring-1 ring-inset ring-white/10 dark:bg-n-heroi-escuro sm:px-7 sm:py-6"
  >
    <span
      aria-hidden="true"
      class="pointer-events-none absolute -end-16 -top-24 size-72 rounded-full border-[3rem] border-n-blue-9 opacity-15"
    />
    <p class="relative mb-0 text-sm font-medium text-white/70">
      {{ rotuloDoMes }}
    </p>
    <h2
      data-numeros-titulo
      class="relative mb-0 text-2xl font-bold leading-tight tracking-tight text-white sm:text-3xl"
    >
      {{ titulo }}
    </h2>
    <p class="relative mb-0 text-base text-white/80">{{ frase }}</p>

    <div v-if="topo.meta" class="relative flex flex-col gap-1.5">
      <div
        role="progressbar"
        :aria-valuenow="pct"
        aria-valuemin="0"
        aria-valuemax="100"
        :aria-valuetext="t(`${P}.TOPO.BARRA`, { pct, esperado: esperado })"
        class="relative h-2.5 w-full overflow-visible rounded-full bg-white/15"
      >
        <div
          class="h-full rounded-full bg-n-amber-9 transition-[width] motion-reduce:transition-none"
          :class="larguraDe(pct)"
        />
        <span
          v-if="!mes.fechado"
          aria-hidden="true"
          data-marca-hoje
          class="absolute -top-[3px] h-4 w-0.5 rounded bg-white/90"
          :class="inicioDe(esperado)"
        />
      </div>
    </div>

    <div
      v-if="(botao && destino) || podeDefinirMetas"
      class="relative flex flex-wrap items-center gap-x-4 gap-y-2 pt-1"
    >
      <RouterLink
        v-if="botao && destino"
        :to="destino.to"
        data-topo-botao
        class="inline-flex min-h-11 items-center gap-2 rounded-xl bg-white px-4 text-sm font-semibold text-n-heroi transition hover:bg-white/90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
      >
        {{ botao }}
        <span
          class="i-lucide-arrow-right size-4 rtl:rotate-180"
          aria-hidden="true"
        />
      </RouterLink>
      <button
        v-if="podeDefinirMetas"
        type="button"
        data-topo-metas
        class="inline-flex min-h-11 items-center gap-1.5 rounded-xl px-2 text-sm font-medium text-white/80 underline-offset-4 hover:text-white hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
        @click="emit('metas')"
      >
        <span class="i-lucide-target size-4" aria-hidden="true" />
        {{ t(`${P}.TOPO.METAS_LINK`, { mes: mesNome }) }}
      </button>
    </div>
  </section>
</template>
