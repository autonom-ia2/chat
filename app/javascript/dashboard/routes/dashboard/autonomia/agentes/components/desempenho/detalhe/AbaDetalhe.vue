<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import CabecalhoDeSecao from '../comum/CabecalhoDeSecao.vue';
import Segmento from '../comum/Segmento.vue';
import TabelaProcuras from './TabelaProcuras.vue';
import TabelaPorPeriodo from './TabelaPorPeriodo.vue';
import TabelaPorTema from './TabelaPorTema.vue';
import TabelaConversasAtivas from './TabelaConversasAtivas.vue';
import TabelaRegras from './TabelaRegras.vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import {
  FILTROS_VAZIOS,
  TABELAS,
  TAMANHO_PADRAO,
  enderecoDaAba,
  tabelaDoEndereco,
} from '../../../utils/desempenhoDetalhe';

// #2226 v2 — a aba Detalhe: os números exatos por trás do Resumo, em 5 tabelas. A tabela escolhida
// e os filtros das procuras vivem no endereço (`?tabela=` e os filtros), para o Resumo trazer a
// pessoa direto para o recorte certo.
defineProps({
  painel: { type: Object, required: true },
  nome: { type: String, default: '' },
});

const route = useRoute();
const router = useRouter();
const { t } = useFormatoDoPainel();
const B = 'AGENTS.DESEMPENHO2.B';

const COMPONENTES = {
  procuras: TabelaProcuras,
  periodo: TabelaPorPeriodo,
  tema: TabelaPorTema,
  ativas: TabelaConversasAtivas,
  regras: TabelaRegras,
};

const opcoes = computed(() =>
  TABELAS.map(id => ({
    value: id,
    label: t(`${B}.TABELAS.${id.toUpperCase()}`),
  }))
);

const tabela = computed({
  get: () => tabelaDoEndereco(route.query),
  set: id => {
    if (id === tabela.value) return;
    router.replace({
      query: enderecoDaAba(route.query, id, { ...FILTROS_VAZIOS }),
    });
  },
});

// Da tabela por tema para as procuras daquele tema, começando do zero nos outros filtros.
const filtrar = filtros => {
  router.replace({
    query: enderecoDaAba(route.query, 'procuras', {
      ...FILTROS_VAZIOS,
      pagina: 1,
      tamanho: TAMANHO_PADRAO,
      ...filtros,
    }),
  });
};
</script>

<template>
  <div class="flex flex-col gap-4" data-aba-detalhe>
    <CabecalhoDeSecao
      id="detalhe"
      :sobre="t(`${B}.SOBRE`)"
      :titulo="nome ? t(`${B}.TITULO_COM_NOME`, { nome }) : t(`${B}.TITULO`)"
      :descricao="t(`${B}.DESCRICAO`)"
    />
    <Segmento v-model="tabela" :opcoes="opcoes" :rotulo="t(`${B}.ESCOLHA`)" />
    <component
      :is="COMPONENTES[tabela]"
      :key="tabela"
      :painel="painel"
      @filtrar="filtrar"
    />
  </div>
</template>
