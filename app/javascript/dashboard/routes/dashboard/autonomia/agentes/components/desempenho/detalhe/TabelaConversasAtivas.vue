<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import TabelaDoPainel from './TabelaDoPainel.vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import {
  hrefDaConversa,
  nomeDe,
  pct as pctDe,
} from '../../../utils/desempenhoContrato';
import { ordenar } from '../../../utils/desempenhoDetalhe';

// #2226 v2 — as conversas que mais pedem no período (top 20 do contrato, na ordem dos pedidos de
// compra — a mesma do "top 10" do Resumo): quantas procuras, quantos pedidos de compra, quantas
// fecharam, primeiro e último contato e o tema mais comum.
const props = defineProps({
  painel: { type: Object, required: true },
});

const router = useRouter();
const { t, n, pct } = useFormatoDoPainel();
const B = 'AGENTS.DESEMPENHO2.B.ATIVAS';
const ordem = ref({ coluna: 'compra', sentido: 'desc' });
const nomes = computed(() => props.painel.meta?.nomes || {});
const ativas = computed(() => props.painel.conversas_ativas || []);

const linhas = computed(() =>
  ordenar(
    ativas.value.map(conversa => ({
      ...conversa,
      chave: String(conversa.conversa),
      visivel: conversa.visivel !== false,
      tema: nomeDe(props.painel.catalogo, 'temas', conversa.tema_id),
    })),
    ordem.value
  )
);

const soma = computed(() =>
  ativas.value.reduce((total, conversa) => total + (conversa.compra || 0), 0)
);
const pctDaSoma = computed(() =>
  pctDe(soma.value, props.painel.funil?.base || 0)
);

const numero = (id, titulo) => ({
  id,
  titulo,
  alinhar: 'fim',
  ordenavel: true,
  formato: 'numero',
});
const colunas = computed(() => [
  { id: 'conversa', titulo: t(`${B}.COL.CONVERSA`), ordenavel: true },
  numero('procuras', t(`${B}.COL.PROCURAS`)),
  numero('compra', nomes.value.compra || t(`${B}.COL.COMPRA`)),
  numero('fecharam', nomes.value.fechou || t(`${B}.COL.FECHARAM`)),
  {
    id: 'primeira',
    titulo: t(`${B}.COL.PRIMEIRA`),
    ordenavel: true,
    formato: 'dataHora',
  },
  {
    id: 'ultima',
    titulo: t(`${B}.COL.ULTIMA`),
    ordenavel: true,
    formato: 'dataHora',
  },
  { id: 'tema', titulo: t(`${B}.COL.TEMA`), ordenavel: true },
]);
</script>

<template>
  <CartaoDoPainel
    :titulo="t(`${B}.TITULO`)"
    :descricao="t(`${B}.DESCRICAO`)"
    :unidade="t(`${B}.UNIDADE`)"
  >
    <p
      v-if="ativas.length"
      class="text-sm text-n-slate-12 tabular-nums"
      data-soma
    >
      {{
        t(`${B}.SOMA`, {
          n: n(ativas.length),
          pct: pct(pctDaSoma),
          procuras: n(soma),
          m: n(painel.funil?.base),
          compra: String(nomes.compra || '').toLocaleLowerCase(),
        })
      }}
    </p>
    <TabelaDoPainel
      :colunas="colunas"
      :linhas="linhas"
      :ordem="ordem"
      :legenda="t(`${B}.TITULO`)"
      largura-minima="min-w-[48rem]"
      @ordenar="ordem = $event"
    >
      <template #celula-conversa="{ linha }">
        <a
          v-if="linha.visivel"
          :href="hrefDaConversa(router, linha.conversa)"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center min-h-11 -my-2.5 font-semibold tabular-nums text-n-blue-11 underline-offset-4 hover:underline"
          :aria-label="
            t('AGENTS.DESEMPENHO2.B.PROCURAS.ABRIR_CONVERSA', {
              n: linha.conversa,
            })
          "
          data-link-conversa
        >
          {{ t('AGENTS.DESEMPENHO2.B.PROCURAS.NUMERO', { n: linha.conversa }) }}
        </a>
        <span v-else class="text-xs text-n-slate-11">{{
          t('AGENTS.DESEMPENHO2.B.PROCURAS.OUTRA_EQUIPE')
        }}</span>
      </template>
      <template #celula-fecharam="{ valor }">
        <span :class="valor ? 'font-semibold text-n-teal-11' : ''">{{
          n(valor)
        }}</span>
      </template>
      <template #celula-tema="{ valor }">
        {{ valor || t('AGENTS.DESEMPENHO2.B.SEM_NOME') }}
      </template>
    </TabelaDoPainel>
  </CartaoDoPainel>
</template>
