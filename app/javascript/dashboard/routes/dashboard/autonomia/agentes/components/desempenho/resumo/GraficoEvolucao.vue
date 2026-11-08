<script setup>
import { computed, ref } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { corDe } from '../../../utils/desempenhoCores';
import {
  ALTURA,
  LARGURA,
  degrauDaBolha,
  escalaJusta,
  indiceDoPico,
  indicesDoEixo,
  tracoDaArea,
  tracoDaLinha,
  tracoDoPonto,
  xDoIndice,
  yDoValor,
} from '../../../utils/desempenhoGrafico';

// #2226 v2 (§2.2) — a linha do tempo do painel, em SVG próprio: grade, eixo Y com números redondos,
// linha principal com área, linha secundária, pontos, o pico marcado com o valor e o último ponto
// tracejado quando o dia (ou a semana) ainda está em andamento. Embaixo, as faixas de eventos na
// mesma escala X (bolha proporcional ao número). Os textos ficam fora do SVG, em HTML: as colunas
// usam flex-1 e caem no meio de cada ponto. Passar o mouse ou usar as setas mostra todos os valores
// daquele ponto; o aria-label já lê a série inteira.
const props = defineProps({
  pontos: { type: Array, required: true },
  // [{ id, nome, cor, valores }] — a primeira é a principal (com área).
  series: { type: Array, required: true },
  // [{ id, nome, cor, valores }] — faixas de eventos embaixo do gráfico.
  faixas: { type: Array, default: () => [] },
  unidade: { type: String, default: 'dia' },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.EVOLUCAO';
const TAMANHO_DA_BOLHA = [
  '',
  'size-1.5',
  'size-2',
  'size-2.5',
  'size-3',
  'size-4',
];
const ESPESSURA = { principal: 2.5, secundaria: 2, ponto: 6 };

const ativo = ref(-1);
const total = computed(() => props.pontos.length);
const principal = computed(() => props.series[0]);
const parcial = computed(() => Boolean(props.pontos[total.value - 1]?.parcial));
const ultimoFirme = computed(() =>
  parcial.value ? total.value - 2 : total.value - 1
);

// 4 ou 5 linhas de grade: a que deixa menos vazio acima do pico.
const escala = computed(() =>
  escalaJusta(Math.max(0, ...props.series.flatMap(serie => serie.valores)))
);
const grade = computed(() => {
  const linhas = escala.value.marcas.length - 1;
  return Array.from({ length: linhas + 1 }, (_, i) => (ALTURA / linhas) * i);
});
const pico = computed(() => indiceDoPico(principal.value?.valores || []));
const datasNoEixo = computed(() => new Set(indicesDoEixo(total.value)));

const rotuloDoPonto = ponto =>
  props.unidade === 'semana'
    ? fmt.t(`${NS}.SEMANA_DE`, { data: fmt.data(ponto.inicio) })
    : fmt.data(ponto.inicio);

const descricao = computed(() =>
  props.series
    .map(serie => {
      const valores = props.pontos
        .map(
          (ponto, i) => `${fmt.data(ponto.inicio)} ${fmt.n(serie.valores[i])}`
        )
        .join(', ');
      return fmt.t(`${NS}.LEITURA_DA_SERIE`, {
        serie: serie.nome,
        unidade: fmt.t(`${NS}.UNIDADE.${props.unidade.toUpperCase()}`),
        valores,
      });
    })
    .join('. ')
);

const alinhamentoDaCaixa = indice => {
  if (indice < total.value / 4) return 'left-0';
  if (indice > (total.value * 3) / 4) return 'right-0';
  return 'left-1/2 -translate-x-1/2';
};

const mover = passo => {
  if (!total.value) return;
  const inicio = ativo.value < 0 ? pico.value : ativo.value;
  ativo.value = Math.min(total.value - 1, Math.max(0, inicio + passo));
};

const maiorDaFaixa = faixa => Math.max(0, ...faixa.valores);
// Com muitas bolinhas, o número fica só na maior (o resto aparece ao passar o mouse ou no toque):
// número em toda coluna vira ruído.
const NUMEROS_NA_FAIXA = 12;
const mostrarNumero = (faixa, valor) =>
  faixa.valores.filter(Boolean).length <= NUMEROS_NA_FAIXA ||
  valor === maiorDaFaixa(faixa);
const somaDe = valores => valores.reduce((acc, valor) => acc + (valor || 0), 0);
</script>

<template>
  <div data-grafico-evolucao class="flex flex-col gap-3">
    <div class="grid grid-cols-[2.5rem_minmax(0,1fr)] gap-x-2 pt-6">
      <div class="flex flex-col justify-between h-64" aria-hidden="true">
        <span
          v-for="marca in escala.marcas"
          :key="marca"
          class="flex items-center justify-end h-0 text-[0.6875rem] tabular-nums text-n-slate-11"
        >
          {{ fmt.n(marca) }}
        </span>
      </div>

      <div
        class="relative h-64 rounded-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-blue-11"
        role="img"
        tabindex="0"
        :aria-label="descricao"
        @focus="ativo = pico"
        @blur="ativo = -1"
        @keydown.left.prevent="mover(-1)"
        @keydown.right.prevent="mover(1)"
      >
        <svg
          :viewBox="`0 0 ${LARGURA} ${ALTURA}`"
          preserveAspectRatio="none"
          class="absolute inset-0 w-full h-full overflow-visible"
          aria-hidden="true"
        >
          <line
            v-for="y in grade"
            :key="y"
            x1="0"
            :x2="LARGURA"
            :y1="y"
            :y2="y"
            class="stroke-n-weak"
            stroke-width="1"
            vector-effect="non-scaling-stroke"
          />
          <rect
            v-if="ativo >= 0"
            :x="xDoIndice(ativo, total) - LARGURA / total / 2"
            y="0"
            :width="LARGURA / total"
            :height="ALTURA"
            class="fill-n-alpha-2"
          />
          <path
            v-if="principal"
            :d="tracoDaArea(principal.valores, escala.topo)"
            class="opacity-10"
            :class="corDe(principal.cor).fill"
          />
          <line
            v-if="pico >= 0 && principal"
            :x1="xDoIndice(pico, total)"
            :x2="xDoIndice(pico, total)"
            y1="0"
            :y2="yDoValor(principal.valores[pico], escala.topo)"
            class="stroke-n-slate-8"
            stroke-width="1"
            stroke-dasharray="3 3"
            vector-effect="non-scaling-stroke"
          />
          <g
            v-for="(serie, s) in series"
            :key="serie.id"
            :data-serie="serie.id"
            fill="none"
            :class="corDe(serie.cor).stroke"
          >
            <path
              :d="tracoDaLinha(serie.valores, escala.topo, 0, ultimoFirme)"
              :stroke-width="s ? ESPESSURA.secundaria : ESPESSURA.principal"
              stroke-linejoin="round"
              stroke-linecap="round"
              vector-effect="non-scaling-stroke"
            />
            <path
              v-if="parcial"
              data-parcial
              :d="
                tracoDaLinha(serie.valores, escala.topo, total - 2, total - 1)
              "
              :stroke-width="s ? ESPESSURA.secundaria : ESPESSURA.principal"
              stroke-dasharray="5 4"
              vector-effect="non-scaling-stroke"
            />
            <path
              v-for="(valor, i) in serie.valores"
              :key="i"
              :d="tracoDoPonto(valor, i, total, escala.topo)"
              :stroke-width="
                ativo === i || pico === i
                  ? ESPESSURA.ponto + 3
                  : ESPESSURA.ponto
              "
              stroke-linecap="round"
              vector-effect="non-scaling-stroke"
            />
          </g>
        </svg>

        <div class="absolute inset-0 flex">
          <div
            v-for="(ponto, i) in pontos"
            :key="ponto.inicio"
            class="relative flex-1 min-w-0"
            @mouseenter="ativo = i"
            @mouseleave="ativo = -1"
          >
            <span
              v-if="i === pico && principal"
              data-pico
              class="absolute top-0 px-1.5 text-[0.6875rem] font-semibold -translate-x-1/2 -translate-y-full rounded-md left-1/2 whitespace-nowrap tabular-nums bg-n-solid-1 ring-1 ring-n-weak"
              :class="corDe(principal.cor).texto"
            >
              {{ fmt.n(principal.valores[i]) }}
            </span>
            <div
              v-if="ativo === i"
              data-caixa
              class="absolute z-20 flex flex-col gap-1 p-2.5 text-xs rounded-lg shadow-lg pointer-events-none top-2 w-max min-w-[9rem] bg-n-slate-12 text-n-slate-1"
              :class="alinhamentoDaCaixa(i)"
            >
              <span class="font-semibold">
                {{ rotuloDoPonto(ponto) }}
                <template v-if="ponto.parcial">{{
                  fmt.t('AGENTS.DESEMPENHO2.A.COMUM.MARCA_PARCIAL')
                }}</template>
              </span>
              <span
                v-for="serie in [...series, ...faixas]"
                :key="serie.id"
                class="flex items-center justify-between gap-3 tabular-nums"
              >
                <span class="flex items-center gap-1.5">
                  <span
                    class="rounded-full size-2"
                    :class="corDe(serie.cor).fundo"
                  />
                  {{ serie.nome }}
                </span>
                <strong class="font-semibold">{{
                  fmt.n(serie.valores[i])
                }}</strong>
              </span>
            </div>
          </div>
        </div>
      </div>

      <span aria-hidden="true" />
      <div class="flex pt-1.5" aria-hidden="true">
        <span
          v-for="(ponto, i) in pontos"
          :key="ponto.inicio"
          class="flex justify-center flex-1 min-w-0 text-[0.6875rem] tabular-nums text-n-slate-11 whitespace-nowrap"
        >
          <template v-if="datasNoEixo.has(i)">
            {{ fmt.data(ponto.inicio)
            }}<template v-if="ponto.parcial">{{
              fmt.t('AGENTS.DESEMPENHO2.A.COMUM.MARCA_PARCIAL')
            }}</template>
          </template>
        </span>
      </div>
    </div>

    <div
      v-for="faixa in faixas"
      :key="faixa.id"
      :data-faixa="faixa.id"
      class="grid grid-cols-[2.5rem_minmax(0,1fr)] gap-x-2"
    >
      <span aria-hidden="true" />
      <div class="flex flex-col gap-1">
        <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
          <span
            class="rounded-full size-2"
            :class="corDe(faixa.cor).fundo"
            aria-hidden="true"
          />
          {{
            fmt.t(`${NS}.FAIXA_TOTAL`, {
              nome: faixa.nome,
              n: fmt.n(somaDe(faixa.valores)),
            })
          }}
        </span>
        <div
          class="flex items-end h-9 rounded-md bg-n-alpha-1"
          aria-hidden="true"
        >
          <div
            v-for="(valor, i) in faixa.valores"
            :key="i"
            class="flex flex-col items-center justify-end flex-1 min-w-0 gap-0.5 pb-1"
          >
            <template v-if="valor">
              <span
                v-if="mostrarNumero(faixa, valor)"
                class="hidden md:block text-[0.625rem] font-semibold leading-none tabular-nums"
                :class="corDe(faixa.cor).texto"
              >
                {{ fmt.n(valor) }}
              </span>
              <span
                class="rounded-full"
                :class="[
                  TAMANHO_DA_BOLHA[degrauDaBolha(valor, maiorDaFaixa(faixa))],
                  corDe(faixa.cor).fundo,
                ]"
              />
            </template>
          </div>
        </div>
      </div>
    </div>

    <p v-if="parcial" data-nota-parcial class="m-0 text-xs text-n-slate-11">
      {{ fmt.t(`${NS}.PARCIAL.${unidade.toUpperCase()}`) }}
    </p>
  </div>
</template>
