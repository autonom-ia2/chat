<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgentesHeroi from '../components/AgentesHeroi.vue';
import AgenteBotao from '../components/AgenteBotao.vue';
import ContratadoCartao from '../components/ContratadoCartao.vue';
import FaixaDoPlano from '../components/pagina/FaixaDoPlano.vue';
import { MODELO_UNIVERSAL } from '../constants/contratados';
import {
  iconeDoPreco,
  linhaDoPreco,
  mostraFaixa,
} from '../utils/planoDoContratado';

// #3270 — o preço e os dias grátis do agente contratado, para os prints do diretor de arte: o cartão do catálogo com
// a linha do preço (com dias grátis e já usados), o herói da página do modelo com o preço, e a faixa da página do
// agente em cada estado (faltam N dias, último dia, pausado e liberado, que não tem faixa), também no tema escuro. O
// plano tem o formato que o servidor manda (Contratados::Gratis.para_tela); os textos vêm do i18n, os mesmos das telas.
const { t, locale } = useI18n();
locale.value = 'pt_BR';

const plano = extra => ({
  dias_gratis: 7,
  preco_mensal_centavos: 19700,
  moeda: 'BRL',
  situacao: 'gratis',
  dias_restantes: 7,
  ...extra,
});

const PAUSADO = plano({ situacao: 'pausado', dias_restantes: null });

const CARTOES = [
  { id: 'cartao-gratis', titulo: 'Cartão: com dias grátis', plano: plano() },
  {
    id: 'cartao-pausado',
    titulo: 'Cartão: pausado (sem grátis)',
    plano: PAUSADO,
  },
];

const FAIXAS = [
  {
    id: 'gratis',
    titulo: 'Faixa: grátis (faltam 5 dias)',
    plano: plano({ dias_restantes: 5 }),
  },
  {
    id: 'falta-um',
    titulo: 'Faixa: grátis (falta 1 dia)',
    plano: plano({ dias_restantes: 1 }),
  },
  {
    id: 'ultimo-dia',
    titulo: 'Faixa: grátis (último dia)',
    plano: plano({ dias_restantes: 0 }),
  },
  { id: 'pausado', titulo: 'Faixa: pausado', plano: PAUSADO },
  {
    id: 'liberado',
    titulo: 'Faixa: liberado (sem faixa)',
    plano: plano({ situacao: 'liberado', dias_restantes: null }),
  },
];

// O herói da página do modelo com a mesma linha que a página monta (linhaDoPreco e iconeDoPreco).
const precoDoHeroi = computed(() => linhaDoPreco(t, plano(), locale.value));
const iconeDoHeroi = iconeDoPreco(plano());
</script>

<template>
  <Story
    title="Agentes/Seguro Viagem Universal (preço e dias grátis)"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant v-for="cartao in CARTOES" :key="cartao.id" :title="cartao.titulo">
      <div
        :data-variante="cartao.id"
        class="w-full px-4 py-6 bg-n-background md:px-6"
      >
        <ul class="flex flex-col max-w-5xl gap-4 p-0 mx-auto list-none">
          <ContratadoCartao
            :modelo="MODELO_UNIVERSAL"
            :plano="cartao.plano"
            pode-usar
          />
        </ul>
      </div>
    </Variant>
    <Variant title="Herói da página do modelo com o preço">
      <div
        data-variante="heroi"
        class="w-full px-4 py-6 bg-n-background md:px-6"
      >
        <div class="max-w-5xl mx-auto">
          <AgentesHeroi
            :titulo="t('AGENTS.CONTRATADOS.MODELO.TITULO')"
            :texto="t('AGENTS.CONTRATADOS.MODELO.TEXTO')"
          >
            <template #detalhe>
              <p
                class="flex items-center gap-2 m-0 text-base font-semibold text-white"
              >
                <span
                  class="size-5 shrink-0"
                  :class="iconeDoHeroi"
                  aria-hidden="true"
                />
                {{ precoDoHeroi }}
              </p>
            </template>
            <template #acoes>
              <AgenteBotao
                variante="branco"
                tamanho="xl"
                class="w-full md:w-auto"
              >
                {{ t('AGENTS.CONTRATADOS.MODELO.CONTRATAR') }}
              </AgenteBotao>
            </template>
          </AgentesHeroi>
        </div>
      </div>
    </Variant>
    <Variant v-for="faixa in FAIXAS" :key="faixa.id" :title="faixa.titulo">
      <div
        :data-variante="faixa.id"
        class="w-full px-4 py-6 bg-n-background md:px-6"
      >
        <div class="flex flex-col max-w-5xl gap-4 mx-auto">
          <FaixaDoPlano v-if="mostraFaixa(faixa.plano)" :plano="faixa.plano" />
        </div>
      </div>
    </Variant>
    <Variant title="Tema escuro: cartão e faixas">
      <div class="dark" data-variante="escuro">
        <div
          class="flex flex-col w-full gap-4 px-4 py-6 bg-n-background md:px-6"
        >
          <ul
            class="flex flex-col max-w-5xl gap-4 p-0 mx-auto list-none w-full"
          >
            <ContratadoCartao
              :modelo="MODELO_UNIVERSAL"
              :plano="plano()"
              pode-usar
            />
          </ul>
          <div class="flex flex-col max-w-5xl gap-4 mx-auto w-full">
            <FaixaDoPlano :plano="plano({ dias_restantes: 0 })" />
            <FaixaDoPlano :plano="PAUSADO" />
          </div>
        </div>
      </div>
    </Variant>
  </Story>
</template>
