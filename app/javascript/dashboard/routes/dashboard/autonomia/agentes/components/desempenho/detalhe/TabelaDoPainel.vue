<script setup>
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';

// #2226 v2 — a tabela base da aba Detalhe: cabeçalho fixo, ordenação por coluna, números à direita
// e tabulares, linha de total e linha que abre embaixo. Cada coluna pode trocar a célula pelo slot
// `celula-<id>`. A 1ª coluna fica presa à esquerda quando a tabela rola para o lado, com uma borda
// que mostra o corte.
const props = defineProps({
  // [{ id, titulo, alinhar: 'inicio'|'fim', ordenavel, formato: 'numero'|'pct'|'data'|'dataHora'|'texto' }]
  colunas: { type: Array, required: true },
  // Cada linha precisa de `chave` única.
  linhas: { type: Array, default: () => [] },
  // { coluna, sentido: 'asc'|'desc' }
  ordem: { type: Object, default: null },
  // Linha "Total" no fim (mesmos ids das colunas). A 1ª coluna mostra `totalTitulo`.
  total: { type: Object, default: null },
  totalTitulo: { type: String, default: '' },
  vazio: { type: String, default: '' },
  // Nome da tabela para o leitor de tela.
  legenda: { type: String, required: true },
  linhaClicavel: { type: Boolean, default: false },
  // Chaves das linhas abertas (slot `expansao`).
  abertas: { type: Array, default: () => [] },
  // Largura mínima no celular (ex.: 'min-w-[56rem]'): a tabela rola dentro do cartão, a página não.
  larguraMinima: { type: String, default: 'min-w-[40rem]' },
});

const emit = defineEmits(['ordenar', 'linha']);
const { t, n, pct, data, dataHora } = useFormatoDoPainel();

const formatar = (valor, formato) => {
  if (valor === null || valor === undefined || valor === '') return '—';
  if (formato === 'numero') return n(valor);
  if (formato === 'pct') return pct(valor);
  if (formato === 'data') return data(valor);
  if (formato === 'dataHora') return dataHora(valor);
  return valor;
};

const ehNumero = coluna => coluna.alinhar === 'fim';
const PRESA = 'sticky start-0 border-e border-n-weak';
const ariaSort = coluna => {
  if (!coluna.ordenavel) return undefined;
  if (props.ordem?.coluna !== coluna.id) return 'none';
  return props.ordem.sentido === 'desc' ? 'descending' : 'ascending';
};
const iconeDaOrdem = coluna => {
  if (props.ordem?.coluna !== coluna.id) return 'i-lucide-arrow-up-down';
  return props.ordem.sentido === 'desc'
    ? 'i-lucide-arrow-down'
    : 'i-lucide-arrow-up';
};

// Clicar de novo inverte; coluna nova começa do maior (número) ou do A (texto).
const ordenarPor = coluna => {
  const mesma = props.ordem?.coluna === coluna.id;
  const inicial = ehNumero(coluna) ? 'desc' : 'asc';
  const invertido = props.ordem?.sentido === 'desc' ? 'asc' : 'desc';
  emit('ordenar', { coluna: coluna.id, sentido: mesma ? invertido : inicial });
};

const celulaDoTotal = (coluna, indice) => {
  if (indice === 0) return props.totalTitulo;
  if (props.total[coluna.id] === undefined) return '';
  return formatar(props.total[coluna.id], coluna.formato);
};

// Quando a tabela é mais larga que o cartão, uma sombra na borda direita avisa que há colunas
// escondidas (some quando a pessoa chega ao fim da rolagem).
const caixa = ref(null);
const temMaisADireita = ref(false);
const medir = () => {
  const el = caixa.value;
  if (!el) return;
  temMaisADireita.value = el.scrollLeft + el.clientWidth < el.scrollWidth - 1;
};
let observador = null;
onMounted(() => {
  medir();
  if (typeof ResizeObserver !== 'undefined' && caixa.value) {
    observador = new ResizeObserver(medir);
    observador.observe(caixa.value);
  }
});
onBeforeUnmount(() => observador?.disconnect());
watch(
  () => [props.linhas, props.colunas],
  () => nextTick(medir)
);

// O clique que já caiu num link ou botão da linha não abre a linha de novo.
const clicarLinha = (linha, evento) => {
  if (!props.linhaClicavel) return;
  if (evento.target.closest?.('a,button')) return;
  emit('linha', linha);
};
</script>

<template>
  <div class="relative">
    <div
      ref="caixa"
      class="max-h-[37.5rem] overflow-auto rounded-xl ring-1 ring-n-weak"
      tabindex="0"
      :aria-label="legenda"
      @scroll.passive="medir"
    >
      <table
        class="relative table-auto w-full divide-y divide-n-weak"
        :class="larguraMinima"
      >
        <caption class="sr-only">
          {{
            legenda
          }}
        </caption>
        <thead>
          <tr>
            <th
              v-for="(coluna, indice) in colunas"
              :key="coluna.id"
              scope="col"
              :aria-sort="ariaSort(coluna)"
              class="sticky top-0 bg-n-solid-2 px-3 py-2 text-xs font-semibold text-n-slate-11 whitespace-nowrap"
              :class="[
                ehNumero(coluna) ? 'text-end' : 'text-start',
                indice === 0 ? `${PRESA} z-[3]` : 'z-[1]',
              ]"
            >
              <button
                v-if="coluna.ordenavel"
                type="button"
                class="inline-flex items-center gap-1 min-h-11 -my-2 rounded-md hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                :class="{ 'flex-row-reverse': ehNumero(coluna) }"
                :data-ordenar="coluna.id"
                @click="ordenarPor(coluna)"
              >
                <span>{{ coluna.titulo }}</span>
                <span
                  class="size-3.5 flex-shrink-0"
                  :class="[
                    iconeDaOrdem(coluna),
                    ordem?.coluna === coluna.id
                      ? 'text-n-blue-11'
                      : 'text-n-slate-9',
                  ]"
                  aria-hidden="true"
                />
              </button>
              <span v-else>{{ coluna.titulo }}</span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr v-if="!linhas.length">
            <td
              :colspan="colunas.length"
              class="px-3 py-8 text-sm text-center text-n-slate-11"
            >
              {{ vazio || t('AGENTS.DESEMPENHO2.B.TABELA.VAZIO') }}
            </td>
          </tr>
          <template v-for="linha in linhas" :key="linha.chave">
            <tr
              class="group hover:bg-n-alpha-1"
              :class="{ 'cursor-pointer': linhaClicavel }"
              :data-linha="linha.chave"
              @click="clicarLinha(linha, $event)"
            >
              <td
                v-for="(coluna, indice) in colunas"
                :key="coluna.id"
                class="px-3 py-1.5 text-sm text-n-slate-12 align-top"
                :class="[
                  ehNumero(coluna)
                    ? 'text-end tabular-nums whitespace-nowrap'
                    : 'text-start',
                  indice === 0
                    ? `${PRESA} z-[2] bg-n-solid-1 group-hover:bg-n-solid-2`
                    : '',
                ]"
              >
                <slot
                  :name="`celula-${coluna.id}`"
                  :linha="linha"
                  :valor="linha[coluna.id]"
                >
                  {{ formatar(linha[coluna.id], coluna.formato) }}
                </slot>
              </td>
            </tr>
            <tr v-if="abertas.includes(linha.chave)" class="bg-n-alpha-1">
              <td :colspan="colunas.length" class="px-3 py-3">
                <slot name="expansao" :linha="linha" />
              </td>
            </tr>
          </template>
        </tbody>
        <tfoot v-if="total && linhas.length">
          <tr class="bg-n-blue-2 font-semibold" data-total>
            <td
              v-for="(coluna, indice) in colunas"
              :key="coluna.id"
              class="px-3 py-1.5 text-sm text-n-slate-12"
              :class="[
                ehNumero(coluna)
                  ? 'text-end tabular-nums whitespace-nowrap'
                  : 'text-start',
                indice === 0 ? `${PRESA} z-[2] bg-n-blue-2` : '',
              ]"
            >
              {{ celulaDoTotal(coluna, indice) }}
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
    <span
      v-if="temMaisADireita"
      data-sombra-direita
      class="absolute inset-y-0 w-8 pointer-events-none end-0 rounded-e-xl bg-gradient-to-l from-n-slate-12/15 to-transparent"
      aria-hidden="true"
    />
  </div>
</template>
