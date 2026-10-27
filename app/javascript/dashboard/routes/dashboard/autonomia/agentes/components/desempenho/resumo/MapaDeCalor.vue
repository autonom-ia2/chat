<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { tomDoMapa, tonsDoMapa } from '../../../utils/desempenhoCores';
import { picoDoMapa } from '../../../utils/desempenhoGrafico';

// #2226 v2 (§2.6) — o mapa de calor dia × hora, sempre visível, com o número dentro de cada célula
// (os números substituem o mouse), coluna e linha Total, o pico destacado e a legenda da escala. As
// 24 horas e o Total cabem no desktop; no celular a grade rola na horizontal dentro do cartão (com o
// aviso de arrastar), a página não.
const props = defineProps({
  // int[7][24]: segunda … domingo × 0 … 23 h.
  mapa: { type: Array, required: true },
  // 'volume' (azul) ou 'alerta' (vermelho, para quem ficou sem uma pessoa).
  tom: { type: String, default: 'volume' },
  rotulo: { type: String, default: '' },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.HORARIOS';
const HORAS = Array.from({ length: 24 }, (_, hora) => hora);

const maximo = computed(() => Math.max(0, ...props.mapa.flat()));
const totalDoDia = dia =>
  props.mapa[dia].reduce((acc, valor) => acc + valor, 0);
const totalDaHora = hora =>
  props.mapa.reduce((acc, linha) => acc + (linha[hora] || 0), 0);
const total = computed(() =>
  props.mapa.flat().reduce((acc, valor) => acc + valor, 0)
);

const pico = computed(() => picoDoMapa(props.mapa));
const ehPico = (dia, hora) =>
  pico.value.valor > 0 && pico.value.dia === dia && pico.value.hora === hora;

const tons = computed(() => tonsDoMapa(props.tom));

const rotuloDaCelula = (dia, hora, valor) =>
  fmt.t(`${NS}.CELULA`, {
    dia: fmt.diaDaSemanaLongo(dia),
    hora,
    n: fmt.n(valor),
  });
</script>

<template>
  <div class="flex flex-col gap-2">
    <p
      data-arrastar
      class="flex items-center gap-1 m-0 text-xs text-n-slate-11 lg:hidden"
    >
      <span class="i-lucide-move-horizontal size-3.5" aria-hidden="true" />
      {{ fmt.t(`${NS}.ARRASTAR`) }}
    </p>
    <div class="pb-1 overflow-x-auto">
      <div
        data-mapa
        role="table"
        :aria-label="rotulo || fmt.t(`${NS}.MAPA_ROTULO`)"
        class="grid grid-cols-[2.25rem_repeat(24,minmax(1.375rem,1fr))_2.75rem] gap-1 min-w-[44rem]"
      >
        <div role="row" class="contents">
          <span role="columnheader" :aria-label="fmt.t(`${NS}.DIA`)" />
          <span
            v-for="hora in HORAS"
            :key="hora"
            role="columnheader"
            class="text-center text-[0.625rem] tabular-nums text-n-slate-11"
          >
            {{ hora }}
          </span>
          <span
            role="columnheader"
            class="text-[0.625rem] font-semibold text-end text-n-slate-12"
          >
            {{ fmt.t(`${NS}.TOTAL`) }}
          </span>
        </div>
        <div
          v-for="(linha, dia) in mapa"
          :key="dia"
          role="row"
          class="contents"
        >
          <span
            role="rowheader"
            class="flex items-center text-xs font-semibold text-n-slate-11"
          >
            {{ fmt.diaDaSemana(dia) }}
          </span>
          <span
            v-for="(valor, hora) in linha"
            :key="hora"
            role="cell"
            :data-celula="`${dia}-${hora}`"
            :data-pico="ehPico(dia, hora) || undefined"
            :aria-label="rotuloDaCelula(dia, hora, valor)"
            class="grid h-7 rounded-md place-items-center text-[0.625rem] font-semibold tabular-nums"
            :class="[
              tomDoMapa(valor, maximo, tom),
              ehPico(dia, hora) ? 'ring-2 ring-n-slate-12' : '',
            ]"
          >
            <span aria-hidden="true">{{ valor ? fmt.n(valor) : '' }}</span>
          </span>
          <span
            role="cell"
            class="flex items-center justify-end text-xs font-bold tabular-nums text-n-slate-12"
          >
            {{ fmt.n(totalDoDia(dia)) }}
          </span>
        </div>
        <div role="row" class="contents">
          <span
            role="rowheader"
            class="flex items-center text-xs font-bold text-n-slate-12"
          >
            {{ fmt.t(`${NS}.TOTAL`) }}
          </span>
          <span
            v-for="hora in HORAS"
            :key="hora"
            role="cell"
            class="text-center text-[0.625rem] font-semibold tabular-nums text-n-slate-12"
          >
            {{ fmt.n(totalDaHora(hora)) }}
          </span>
          <span
            role="cell"
            data-total-geral
            class="text-xs font-bold text-end tabular-nums text-n-slate-12"
          >
            {{ fmt.n(total) }}
          </span>
        </div>
      </div>
    </div>
    <p
      data-legenda-mapa
      class="flex flex-wrap items-center gap-1.5 m-0 text-xs text-n-slate-11"
    >
      {{ fmt.t(`${NS}.MENOS`) }}
      <span
        v-for="(classe, degrau) in tons"
        :key="degrau"
        class="rounded size-3.5 ring-1 ring-n-weak"
        :class="classe"
        aria-hidden="true"
      />
      {{ fmt.t(`${NS}.MAIS`) }}
      <span aria-hidden="true">{{
        fmt.t('AGENTS.DESEMPENHO2.A.COMUM.SEPARADOR')
      }}</span>
      <span class="tabular-nums">
        {{ fmt.t(`${NS}.MAXIMO`, { n: fmt.n(maximo) }) }}
      </span>
    </p>
  </div>
</template>
