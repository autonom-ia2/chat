<script setup>
import { computed, ref } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { corDe } from '../../../utils/desempenhoCores';
import LinkDaConversa from './LinkDaConversa.vue';

// #2226 v2 — o ranking de barras horizontais da referência: rótulo | trilho | valor + %, um item por
// linha, na cor da série. Mostra os `limite` primeiros e "Ver todos" abre o resto. Item com
// `exemplos` ganha "Exemplos (n)" na mesma linha do número (as conversas que provam abrem embaixo). Com `clicavel`, o rótulo vira botão e
// emite `escolher` (o Resumo leva até a tabela filtrada). Valor null (taxa sem base) mostra "—".
const props = defineProps({
  // [{ id, nome, valor, pct, cor?, extra?, exemplos? }]
  itens: { type: Array, required: true },
  cor: { type: String, default: 'volume' },
  maximo: { type: Number, default: 0 },
  limite: { type: Number, default: 8 },
  rotulo: { type: String, required: true },
  clicavel: { type: Boolean, default: false },
  // 'numero' (procuras, com a pílula de %) ou 'pct' (o próprio valor é uma taxa).
  formato: { type: String, default: 'numero' },
});

const emit = defineEmits(['escolher']);

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.COMUM';
const todos = ref(false);
const abertos = ref([]);
const alternar = id => {
  abertos.value = abertos.value.includes(id)
    ? abertos.value.filter(item => item !== id)
    : [...abertos.value, id];
};

const maior = computed(
  () => props.maximo || Math.max(0, ...props.itens.map(item => item.valor || 0))
);
const visiveis = computed(() =>
  todos.value ? props.itens : props.itens.slice(0, props.limite)
);
const largura = valor =>
  maior.value ? Math.max(0, Math.min(100, (valor / maior.value) * 100)) : 0;
const valorDo = item =>
  props.formato === 'pct' ? fmt.pct(item.valor) : fmt.n(item.valor);
const temPct = item =>
  props.formato !== 'pct' && item.pct !== null && item.pct !== undefined;
const nomeDo = item => item.nome || fmt.t(`${NS}.SEM_NOME`);

// A coluna do valor tem largura fixa: os trilhos terminam todos no mesmo x e a soma se confere em
// coluna. Com a pílula de %, ela é mais larga.
const comPct = computed(() => props.itens.some(temPct));
const comExemplos = computed(() =>
  props.itens.some(item => item.exemplos?.length)
);
const COLUNAS = {
  simples:
    'grid-cols-[minmax(6rem,16rem)_minmax(2.5rem,1fr)_4rem] md:grid-cols-[minmax(9rem,16rem)_minmax(3rem,1fr)_4.5rem]',
  pct: 'grid-cols-[minmax(6rem,16rem)_minmax(2.5rem,1fr)_7rem] md:grid-cols-[minmax(9rem,16rem)_minmax(3rem,1fr)_7.5rem]',
  simplesComExemplos:
    'grid-cols-[minmax(6rem,16rem)_minmax(2.5rem,1fr)_4rem_auto] md:grid-cols-[minmax(9rem,16rem)_minmax(3rem,1fr)_4.5rem_8rem]',
  pctComExemplos:
    'grid-cols-[minmax(6rem,16rem)_minmax(2.5rem,1fr)_7rem_auto] md:grid-cols-[minmax(9rem,16rem)_minmax(3rem,1fr)_7.5rem_8rem]',
};
const colunas = computed(() => {
  const base = comPct.value ? 'pct' : 'simples';
  return COLUNAS[comExemplos.value ? `${base}ComExemplos` : base];
});
</script>

<template>
  <div class="flex flex-col gap-1">
    <p v-if="!itens.length" data-vazio class="m-0 text-sm text-n-slate-11">
      {{ fmt.t(`${NS}.NADA_NO_PERIODO`) }}
    </p>
    <ul
      v-else
      data-ranking
      :aria-label="rotulo"
      class="flex flex-col gap-1.5 p-0 m-0 list-none"
    >
      <li
        v-for="item in visiveis"
        :key="item.id"
        data-item
        class="flex flex-col gap-0.5"
      >
        <div class="grid items-center gap-x-3" :class="colunas">
          <button
            v-if="clicavel"
            type="button"
            class="flex items-center min-w-0 text-sm leading-tight rounded-md text-start min-h-11 text-n-slate-12 hover:text-n-blue-11 hover:underline underline-offset-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
            @click="emit('escolher', item)"
          >
            <span class="line-clamp-2">{{ nomeDo(item) }}</span>
          </button>
          <span
            v-else
            class="text-sm leading-tight min-w-0 line-clamp-2 text-n-slate-12"
          >
            {{ nomeDo(item) }}
          </span>
          <svg
            viewBox="0 0 100 14"
            preserveAspectRatio="none"
            class="w-full h-3.5"
            aria-hidden="true"
          >
            <rect width="100" height="14" rx="7" class="fill-n-slate-3" />
            <rect
              :width="largura(item.valor)"
              height="14"
              rx="7"
              :class="corDe(item.cor || cor).fill"
            />
          </svg>
          <span class="flex items-center justify-end min-w-0 gap-1.5">
            <span
              data-valor
              class="text-sm font-semibold tabular-nums text-n-slate-12"
            >
              {{ valorDo(item) }}
            </span>
            <span
              v-if="temPct(item)"
              class="px-2 text-xs rounded-full tabular-nums bg-n-alpha-2 text-n-slate-11"
            >
              {{ fmt.pct(item.pct) }}
            </span>
          </span>
          <template v-if="comExemplos">
            <button
              v-if="item.exemplos?.length"
              type="button"
              data-exemplos
              class="flex items-center justify-end gap-1 text-xs font-semibold rounded-md min-h-11 whitespace-nowrap shrink-0 text-n-blue-11 hover:underline underline-offset-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
              :aria-expanded="abertos.includes(item.id)"
              @click="alternar(item.id)"
            >
              <span
                class="transition-transform i-lucide-chevron-right size-3.5"
                :class="{ 'rotate-90': abertos.includes(item.id) }"
                aria-hidden="true"
              />
              {{ fmt.t(`${NS}.EXEMPLOS`, { n: item.exemplos.length }) }}
            </button>
            <span v-else aria-hidden="true" />
          </template>
        </div>
        <div
          v-if="item.extra || $slots.extra"
          class="text-xs text-n-slate-11 tabular-nums"
        >
          <slot name="extra" :item="item">{{ item.extra }}</slot>
        </div>
        <ul
          v-if="item.exemplos?.length && abertos.includes(item.id)"
          data-exemplos-abertos
          class="flex flex-col gap-1 p-0 pl-5 m-0 list-none"
        >
          <li
            v-for="prova in item.exemplos"
            :key="`${prova.conversa}-${prova.procura}`"
          >
            <LinkDaConversa :prova="prova" com-resumo />
          </li>
        </ul>
      </li>
    </ul>
    <button
      v-if="itens.length > limite"
      type="button"
      data-ver-todos
      class="self-start text-sm font-semibold rounded-md min-h-11 text-n-blue-11 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      @click="todos = !todos"
    >
      {{
        todos
          ? fmt.t(`${NS}.VER_MENOS`)
          : fmt.t(`${NS}.VER_TODOS`, { n: itens.length })
      }}
    </button>
  </div>
</template>
