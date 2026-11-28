<script setup>
import { useI18n } from 'vue-i18n';
import ContratadoCartao from '../components/ContratadoCartao.vue';
import FaixaDoPlano from '../components/pagina/FaixaDoPlano.vue';
import { MODELO_UNIVERSAL } from '../constants/contratados';
import { mostraFaixa } from '../utils/planoDoContratado';

// #3270 — o preço e o período grátis do agente contratado, para os prints do diretor de arte: o cartão do catálogo com
// a linha do preço e a faixa da página do agente nos três estados (grátis, pausado e liberado, que não tem faixa). O
// plano tem o formato que o servidor manda (Contratados::Gratis.para_tela); os textos vêm do i18n, os mesmos das telas.
useI18n().locale.value = 'pt_BR';

const plano = extra => ({
  dias_gratis: 7,
  preco_mensal_centavos: 19700,
  moeda: 'BRL',
  situacao: 'gratis',
  dias_restantes: 7,
  ...extra,
});

const FAIXAS = [
  {
    id: 'gratis',
    titulo: 'Faixa: grátis (faltam 5 dias)',
    plano: plano({ dias_restantes: 5 }),
  },
  {
    id: 'ultimo-dia',
    titulo: 'Faixa: grátis (último dia)',
    plano: plano({ dias_restantes: 1 }),
  },
  {
    id: 'pausado',
    titulo: 'Faixa: pausado',
    plano: plano({ situacao: 'pausado', dias_restantes: null }),
  },
  {
    id: 'liberado',
    titulo: 'Faixa: liberado (sem faixa)',
    plano: plano({ situacao: 'liberado', dias_restantes: null }),
  },
];
</script>

<template>
  <Story
    title="Agentes/Seguro Viagem Universal (preço e período grátis)"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Cartão do catálogo com o preço">
      <div class="w-full min-h-screen px-4 py-6 bg-n-background md:px-6">
        <ul class="flex flex-col max-w-5xl gap-4 p-0 mx-auto list-none">
          <ContratadoCartao
            :modelo="MODELO_UNIVERSAL"
            :plano="plano()"
            pode-usar
          />
        </ul>
      </div>
    </Variant>
    <Variant v-for="faixa in FAIXAS" :key="faixa.id" :title="faixa.titulo">
      <div
        :data-variante="faixa.id"
        class="w-full min-h-screen px-4 py-6 bg-n-background md:px-6"
      >
        <div class="flex flex-col max-w-5xl gap-4 mx-auto">
          <FaixaDoPlano v-if="mostraFaixa(faixa.plano)" :plano="faixa.plano" />
        </div>
      </div>
    </Variant>
  </Story>
</template>
