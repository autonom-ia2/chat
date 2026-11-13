<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  chaveDoDestino,
  contadoresDosSeguros,
  destinosDeSeguro,
  destinosQueFaltam,
  ehProblemaDoSeguro,
  numerosDosSeguros,
  segurosConferidos,
  segurosPorTipo,
} from '../../../carteira/segurosDaPlanilha';
import { chaveDoTipo } from '../../../carteira/tiposDeSeguro';
import { useIdioma } from '../../../ficha/idioma';
import { planilhaApagada } from '../../../trazer/contagem';
import { ERROS } from '../../../trazer/falhasDaTela';
import ErroComTentarDeNovo from '../../comum/ErroComTentarDeNovo.vue';
import OQueVouGuardar from '../../trazer/OQueVouGuardar.vue';
import PrecisamDeVoce from '../../trazer/PrecisamDeVoce.vue';
import ContadoresDosSeguros from './ContadoresDosSeguros.vue';
import ExemplosComSeguros from './ExemplosComSeguros.vue';
import ProblemaDoSeguro from './ProblemaDoSeguro.vue';

// #2897 — "Conferir" da planilha que tem seguros. Tem dois momentos:
//   1. falta apontar coluna obrigatória do seguro (o número da apólice, a
//      seguradora, o tipo ou quando termina): a tela diz quais faltam e já
//      mostra as colunas abertas. O Trazer continua ligado: o clique diz o que
//      falta, como alerta, e leva o foco até lá (`faltam`, `pedidos`);
//   2. as colunas estão apontadas e as linhas foram conferidas como seguro:
//      quantos seguros entram e de quantas pessoas, os contadores, os seguros
//      por tipo (o tipo de cada um já vem decidido), as fichas de exemplo com
//      os seguros, as linhas que precisam da pessoa e o botão único de trazer.
// Todo número diz o que conta ("12 seguros de 9 pessoas"). As peças das linhas
// e das colunas são as da tela das listas, com os destinos e os problemas de
// seguro a mais.
const props = defineProps({
  leitura: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
  relendo: { type: Boolean, default: false },
  comErro: { type: Boolean, default: false },
  recusaDoConserto: { type: Object, default: null },
  recusaDaColuna: { type: Object, default: null },
  // O erro da tela (ERROS de trazer/falhasDaTela.js).
  recusaDoTrazer: { type: String, default: '' },
  faltamCarregar: { type: Number, default: 0 },
  carregandoMais: { type: Boolean, default: false },
  erroDoMais: { type: Boolean, default: false },
  // Os destinos obrigatórios sem coluna, depois que a pessoa pediu para trazer
  // (antes disso, vazio), e quantas vezes ela já pediu.
  faltam: { type: Array, default: () => [] },
  pedidos: { type: Number, default: 0 },
});
const emit = defineEmits([
  'guardar',
  'deixarDeFora',
  'reabrir',
  'trocar',
  'mostrarMais',
  'trazer',
  'voltar',
  'tentar',
  'escolherOutra',
]);

const { t } = useI18n();
const idioma = useIdioma();
const BASE = 'RELACIONAMENTOS_CARTEIRA.TRAZER';

const raiz = ref(null);
const alerta = ref(null);
const idDoAlerta = useId();

const conferidos = computed(() => segurosConferidos(props.leitura));
const numeros = computed(() => numerosDosSeguros(props.leitura));
const contadores = computed(() => contadoresDosSeguros(props.leitura));
const semNinguemParaTrazer = computed(
  () => props.recusaDoTrazer === ERROS.NADA_PARA_TRAZER
);

// "Achei 12 seguros de 9 pessoas."
const frase = computed(() => {
  const { seguros, pessoas } = numeros.value;
  return [
    t(`${BASE}.CONFERIR.ACHEI`, { count: seguros }, seguros),
    t(`${BASE}.CONFERIR.DE_PESSOAS`, { count: pessoas }, pessoas),
  ].join(' ');
});
// "Trazer 12 seguros de 9 pessoas"
const rotuloDoTrazer = computed(() => {
  const { seguros, pessoas } = numeros.value;
  return [
    t(`${BASE}.CONFERIR.TRAZER`, { count: seguros }, seguros),
    t(`${BASE}.CONFERIR.TRAZER_DE`, { count: pessoas }, pessoas),
  ].join(' ');
});

const porTipo = computed(() =>
  segurosPorTipo(props.leitura).map(({ tipo, count }) => ({
    tipo,
    texto: t(
      `${BASE}.CONFERIR.POR_TIPO`,
      { tipo: t(chaveDoTipo(tipo)), count },
      count
    ),
  }))
);

// Os destinos de seguro que as colunas podem ter, com o nome de cada um.
const destinosAMais = computed(() =>
  destinosDeSeguro(props.leitura).map(({ value, chave }) => ({
    value,
    label: t(chave),
  }))
);

// O que ainda falta apontar, pelo nome que a tela dá a cada coluna.
// O destino que a tela não conhece não tem nome para dizer.
const nomesDe = destinos =>
  destinos.filter(chaveDoDestino).map(destino => t(chaveDoDestino(destino)));
const queFaltam = computed(() => nomesDe(destinosQueFaltam(props.leitura)));
// "Número da apólice, Seguradora e Tipo de seguro", no idioma do painel.
const emLista = nomes =>
  new Intl.ListFormat(idioma.value, { type: 'conjunction' }).format(nomes);
const fraseDoQueFalta = computed(() =>
  props.faltam.length
    ? t(`${BASE}.COLUNAS.FALTA`, { lista: emLista(nomesDe(props.faltam)) })
    : ''
);

// A pessoa pediu para trazer com coluna faltando: o foco vai ao alerta.
watch(
  () => props.pedidos,
  async pedidos => {
    if (!pedidos) return;
    await nextTick();
    alerta.value?.focus();
  }
);

const cartaoDe = problema =>
  ehProblemaDoSeguro(problema) ? ProblemaDoSeguro : null;

const irParaAsLinhas = () => {
  const secao = raiz.value?.querySelector(
    '[data-relacionamentos="precisam-de-voce"]'
  );
  if (!secao) return;
  const reduz = window.matchMedia?.(
    '(prefers-reduced-motion: reduce)'
  )?.matches;
  secao.scrollIntoView({ behavior: reduz ? 'auto' : 'smooth', block: 'start' });
  secao
    .querySelector('[data-relacionamentos="precisam-titulo"]')
    ?.focus({ preventScroll: true });
};
</script>

<template>
  <section
    ref="raiz"
    data-carteira="conferir-seguros"
    :data-conferidos="conferidos ? 'sim' : 'nao'"
    class="flex flex-col gap-10"
  >
    <div v-if="conferidos" class="flex flex-col gap-6">
      <h1
        data-titulo-da-tela
        tabindex="-1"
        class="m-0 text-3xl font-bold leading-tight tracking-tight outline-none md:text-4xl text-n-slate-12 text-balance"
      >
        {{ frase }}
      </h1>
      <ContadoresDosSeguros
        v-if="contadores.length"
        :contadores="contadores"
        @precisam="irParaAsLinhas"
      />
      <ul
        v-if="porTipo.length"
        data-carteira="seguros-por-tipo"
        :aria-label="t(`${BASE}.CONFERIR.POR_TIPO_LISTA`)"
        class="flex flex-wrap p-0 m-0 text-base list-none gap-x-6 gap-y-1 text-n-slate-11"
      >
        <li v-for="item in porTipo" :key="item.tipo" :data-tipo="item.tipo">
          {{ item.texto }}
        </li>
      </ul>
      <p
        v-if="numeros.repetidos > 0"
        data-carteira="linhas-repetidas"
        class="m-0 text-base text-n-slate-11"
      >
        {{
          t(
            `${BASE}.CONFERIR.REPETIDOS`,
            { count: numeros.repetidos },
            numeros.repetidos
          )
        }}
      </p>
    </div>
    <div v-else class="flex flex-col gap-4">
      <h1
        data-titulo-da-tela
        tabindex="-1"
        class="m-0 text-3xl font-bold leading-tight tracking-tight outline-none md:text-4xl text-n-slate-12"
      >
        {{ t(`${BASE}.COLUNAS.TITULO`) }}
      </h1>
      <p class="m-0 text-lg text-n-slate-11">
        {{ t(`${BASE}.COLUNAS.APOIO`) }}
      </p>
      <ul
        data-carteira="colunas-que-faltam"
        :aria-label="t(`${BASE}.COLUNAS.LISTA`)"
        class="flex flex-col gap-1 m-0 text-base font-medium list-disc ps-5 text-n-slate-12"
      >
        <li v-for="nome in queFaltam" :key="nome">{{ nome }}</li>
      </ul>
    </div>

    <ExemplosComSeguros v-if="conferidos" :exemplos="leitura.exemplos" />

    <PrecisamDeVoce
      v-if="conferidos && (leitura.problemas.length || faltamCarregar > 0)"
      :problemas="leitura.problemas"
      :ocupado="ocupado"
      :sem-conserto="planilhaApagada(leitura)"
      :recusa="recusaDoConserto"
      :faltam-carregar="faltamCarregar"
      :carregando-mais="carregandoMais"
      :erro-do-mais="erroDoMais"
      :cartao-de="cartaoDe"
      @mostrar-mais="emit('mostrarMais')"
      @guardar="(linha, valor) => emit('guardar', linha, valor)"
      @deixar-de-fora="linha => emit('deixarDeFora', linha)"
      @reabrir="linha => emit('reabrir', linha)"
    />

    <OQueVouGuardar
      :key="conferidos ? 'conferidos' : 'faltam'"
      :colunas="leitura.colunas"
      :ocupado="ocupado"
      :relendo="relendo"
      :recusa="recusaDaColuna"
      :tem-empresa="leitura.temEmpresa"
      :destinos-a-mais="destinosAMais"
      :comeca-aberto="!conferidos"
      @trocar="(...troca) => emit('trocar', ...troca)"
    />

    <div class="flex flex-col gap-4">
      <p
        v-if="fraseDoQueFalta"
        :id="idDoAlerta"
        ref="alerta"
        data-carteira="falta-coluna"
        role="alert"
        tabindex="-1"
        class="m-0 text-base font-medium outline-none text-n-ruby-11 focus-visible:underline"
      >
        {{ fraseDoQueFalta }}
      </p>
      <p
        v-if="conferidos && numeros.seguros === 0"
        data-carteira="nenhum-seguro"
        class="m-0 text-base font-medium text-n-slate-12"
      >
        {{ t(`${BASE}.CONFERIR.SEM_SEGUROS`) }}
      </p>
      <p
        v-if="semNinguemParaTrazer"
        data-carteira="recusa-do-trazer"
        role="alert"
        class="m-0 text-base font-medium text-n-ruby-11"
      >
        {{ t('RELACIONAMENTOS_TRAZER.ERROS.NADA_PARA_TRAZER') }}
      </p>
      <div v-if="comErro" data-carteira="erro">
        <ErroComTentarDeNovo
          :mensagem="t('RELACIONAMENTOS_TRAZER.ERROS.TRAZER')"
          @tentar="emit('tentar')"
        />
      </div>
      <div class="flex flex-wrap items-center gap-3">
        <Button
          v-if="conferidos && numeros.seguros === 0"
          data-carteira="escolher-outra"
          size="lg"
          :label="t('RELACIONAMENTOS_TRAZER.CONFERIR.ESCOLHER_OUTRA')"
          :disabled="ocupado"
          @click="emit('escolherOutra')"
        />
        <Button
          v-else
          data-carteira="trazer-seguros"
          size="lg"
          :label="conferidos ? rotuloDoTrazer : t(`${BASE}.COLUNAS.TRAZER`)"
          :disabled="ocupado"
          :aria-describedby="fraseDoQueFalta ? idDoAlerta : undefined"
          @click="emit('trazer')"
        />
        <Button
          slate
          faded
          size="lg"
          data-carteira="voltar"
          :label="t('RELACIONAMENTOS.COMUM.VOLTAR')"
          :disabled="ocupado"
          @click="emit('voltar')"
        />
        <p
          data-carteira="relendo"
          role="status"
          class="m-0 text-base text-n-slate-11"
        >
          {{ relendo ? t('RELACIONAMENTOS_TRAZER.CONFERIR.RELENDO') : '' }}
        </p>
      </div>
    </div>
  </section>
</template>
