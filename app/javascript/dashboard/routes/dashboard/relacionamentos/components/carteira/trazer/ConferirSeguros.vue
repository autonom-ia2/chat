<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  SITUACAO_DA_COLUNA,
  chaveDoDestino,
  colunasDosSeguros,
  colunasParaConfirmar,
  colunasQueServem,
  comAEscolhaDaColuna,
  contadoresDosSeguros,
  destinosDeSeguro,
  ehProblemaDoSeguro,
  numerosDosSeguros,
  obrigatoriosSemColuna,
  segurosConferidos,
  segurosPorTipo,
} from '../../../carteira/segurosDaPlanilha';
import { chaveDoTipo } from '../../../carteira/tiposDeSeguro';
import { useIdioma } from '../../../ficha/idioma';
import { planilhaApagada } from '../../../trazer/contagem';
import { ERROS } from '../../../trazer/falhasDaTela';
import { larguraDaBarra } from '../../../trazer/larguraDaBarra';
import ErroComTentarDeNovo from '../../comum/ErroComTentarDeNovo.vue';
import OQueVouGuardar from '../../trazer/OQueVouGuardar.vue';
import PrecisamDeVoce from '../../trazer/PrecisamDeVoce.vue';
import ColunasDosSeguros from './ColunasDosSeguros.vue';
import ContadoresDosSeguros from './ContadoresDosSeguros.vue';
import ExemplosComSeguros from './ExemplosComSeguros.vue';
import ProblemaDoSeguro from './ProblemaDoSeguro.vue';

// #2897 — "Conferir" da planilha que tem seguros. Tem três momentos:
//   1. onde estão os seguros: uma linha para cada coisa do seguro (o número da
//      apólice, a seguradora, o tipo, quando termina…) com a coluna da planilha
//      em que ela está. A tela chega com o que o servidor sugeriu, e a pessoa
//      só confirma ("Está certo"), troca o que estiver errado ou aponta o que
//      faltou. O botão nunca fica desligado por falta de coluna: o clique diz o
//      que falta, como alerta, e leva o foco até lá;
//   2. as colunas estão confirmadas e as linhas foram conferidas como seguro:
//      quantos seguros entram e de quantas pessoas, os contadores, os seguros
//      por tipo (o tipo de cada um já vem decidido), as fichas de exemplo com
//      os seguros, as linhas que precisam da pessoa e o botão único de trazer;
//   3. a lista está sendo trazida (`trazendo`): a tela continua a mesma, com
//      os números, e no lugar dos botões diz quanto falta.
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
  // A confirmação das colunas: em voo, e se parou no meio.
  conferindo: { type: Boolean, default: false },
  erroAoConferir: { type: Boolean, default: false },
  // A lista está sendo trazida, quanto já foi e se o andamento não veio.
  trazendo: { type: Boolean, default: false },
  porcentagem: { type: Number, default: 0 },
  erroNoAndamento: { type: Boolean, default: false },
});
const emit = defineEmits([
  'guardar',
  'deixarDeFora',
  'reabrir',
  'trocar',
  'confirmar',
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
const desfazendoOutraLista = computed(
  () => props.recusaDoTrazer === ERROS.DESFAZER_EM_CURSO
);
// Nada na tela muda enquanto uma escrita anda, as colunas são confirmadas ou a
// lista é trazida.
const parado = computed(
  () => props.ocupado || props.conferindo || props.trazendo
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

// ---- onde estão os seguros (antes de as linhas serem conferidas) --------------

// O que a pessoa escolheu na tela e ainda não confirmou. Vale para a leitura
// que está na tela: a planilha lida de novo começa do que o servidor guarda.
const mexidas = ref({});
// Os obrigatórios sem coluna que o último clique achou, e quantos cliques
// foram (cada um leva o foco ao alerta de novo).
const faltam = ref([]);
const pedidos = ref(0);

const linhasDasColunas = computed(() =>
  colunasDosSeguros(props.leitura, mexidas.value)
);
const colunasParaApontar = computed(() => colunasQueServem(props.leitura));
// O servidor sugeriu ao menos uma coluna: a tela pede só a confirmação.
const temSugestao = computed(() =>
  linhasDasColunas.value.some(
    ({ situacao }) => situacao === SITUACAO_DA_COLUNA.SUGERIDA
  )
);

watch(
  () => [props.leitura.id, conferidos.value],
  () => {
    mexidas.value = {};
    faltam.value = [];
  }
);

const apontar = (destino, coluna) => {
  mexidas.value = comAEscolhaDaColuna(
    props.leitura,
    mexidas.value,
    destino,
    coluna
  );
  // O que a pessoa acabou de apontar deixa de faltar.
  const ainda = obrigatoriosSemColuna(linhasDasColunas.value);
  faltam.value = faltam.value.filter(falta => ainda.includes(falta));
};

// "Número da apólice, Seguradora e Tipo de seguro", no idioma do painel. O
// destino que a tela não conhece não tem nome para dizer.
const emLista = destinos =>
  new Intl.ListFormat(idioma.value, { type: 'conjunction' }).format(
    destinos.filter(chaveDoDestino).map(destino => t(chaveDoDestino(destino)))
  );
const fraseDoQueFalta = computed(() =>
  faltam.value.length
    ? t(`${BASE}.COLUNAS.FALTA`, { lista: emLista(faltam.value) })
    : ''
);

// "Está certo": com obrigatório sem coluna, a tela diz qual falta e nada vai
// ao servidor; senão, sobem as colunas da tela que ele ainda não guarda.
const confirmar = async () => {
  faltam.value = obrigatoriosSemColuna(linhasDasColunas.value);
  if (faltam.value.length) {
    pedidos.value += 1;
    await nextTick();
    alerta.value?.focus();
    return;
  }
  emit('confirmar', colunasParaConfirmar(linhasDasColunas.value));
};

// O que a tela está fazendo agora, dito a quem não vê o botão girar.
const fraseDoAndamento = computed(() => {
  if (props.conferindo) return t(`${BASE}.COLUNAS.GUARDANDO`);
  return props.relendo ? t('RELACIONAMENTOS_TRAZER.CONFERIR.RELENDO') : '';
});

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
      <p
        v-if="numeros.cancelados > 0"
        data-carteira="seguros-cancelados"
        class="m-0 text-base text-n-slate-11"
      >
        {{
          t(
            `${BASE}.CONFERIR.CANCELADOS`,
            { count: numeros.cancelados },
            numeros.cancelados
          )
        }}
      </p>
      <p
        v-if="numeros.semTelefone > 0"
        data-carteira="entram-sem-telefone"
        class="p-3 m-0 text-base rounded-xl bg-n-amber-3 text-n-amber-11"
      >
        {{
          t(
            'RELACIONAMENTOS_TRAZER.CONFERIR.ENTRAM_SEM_TELEFONE',
            { count: numeros.semTelefone },
            numeros.semTelefone
          )
        }}
      </p>
    </div>
    <template v-else>
      <div class="flex flex-col gap-4">
        <h1
          data-titulo-da-tela
          tabindex="-1"
          class="m-0 text-3xl font-bold leading-tight tracking-tight outline-none md:text-4xl text-n-slate-12 text-balance"
        >
          {{
            t(
              temSugestao
                ? `${BASE}.COLUNAS.TITULO_SUGERIDO`
                : `${BASE}.COLUNAS.TITULO`
            )
          }}
        </h1>
        <p class="m-0 text-lg text-n-slate-11">
          {{
            t(
              temSugestao
                ? `${BASE}.COLUNAS.APOIO_SUGERIDO`
                : `${BASE}.COLUNAS.APOIO`
            )
          }}
        </p>
      </div>
      <ColunasDosSeguros
        :linhas="linhasDasColunas"
        :colunas="colunasParaApontar"
        :ocupado="parado"
        :faltam="faltam"
        :id-do-alerta="fraseDoQueFalta ? idDoAlerta : undefined"
        @apontar="apontar"
      />
    </template>

    <ExemplosComSeguros v-if="conferidos" :exemplos="leitura.exemplos" />

    <PrecisamDeVoce
      v-if="
        conferidos &&
        !trazendo &&
        (leitura.problemas.length || faltamCarregar > 0)
      "
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
      v-if="conferidos && !trazendo"
      :colunas="leitura.colunas"
      :ocupado="ocupado"
      :relendo="relendo"
      :recusa="recusaDaColuna"
      :tem-empresa="leitura.temEmpresa"
      :destinos-a-mais="destinosAMais"
      @trocar="(...troca) => emit('trocar', ...troca)"
    />

    <div
      v-if="trazendo"
      data-carteira="trazendo-seguros"
      class="flex flex-col gap-4 p-6 border rounded-3xl border-n-weak bg-n-solid-1"
    >
      <p
        role="status"
        class="m-0 text-xl font-semibold tabular-nums text-n-slate-12"
      >
        {{ t(`${BASE}.CONFERIR.TRAZENDO`, { porcentagem }) }}
      </p>
      <div
        role="progressbar"
        :aria-label="t('RELACIONAMENTOS_TRAZER.ANDAMENTO.ROTULO')"
        aria-valuemin="0"
        aria-valuemax="100"
        :aria-valuenow="porcentagem"
        class="h-3 overflow-hidden rounded-full bg-n-alpha-2"
      >
        <div
          class="h-full rounded-full bg-n-blue-11 dark:bg-n-blue-9"
          :class="larguraDaBarra(porcentagem)"
        />
      </div>
      <p class="m-0 text-base text-n-slate-11">
        {{ t('RELACIONAMENTOS_TRAZER.ANDAMENTO.APOIO') }}
      </p>
      <div v-if="erroNoAndamento" data-carteira="erro">
        <ErroComTentarDeNovo
          :mensagem="t('RELACIONAMENTOS_TRAZER.ERROS.ANDAMENTO')"
          @tentar="emit('tentar')"
        />
      </div>
    </div>

    <div v-if="!trazendo" class="flex flex-col gap-4">
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
      <p
        v-if="desfazendoOutraLista"
        data-carteira="recusa-do-trazer"
        role="alert"
        class="m-0 text-base font-medium text-n-ruby-11"
      >
        {{ t('RELACIONAMENTOS_TRAZER.ERROS.DESFAZER_EM_CURSO') }}
      </p>
      <div v-if="comErro" data-carteira="erro">
        <ErroComTentarDeNovo
          :mensagem="t('RELACIONAMENTOS_TRAZER.ERROS.TRAZER')"
          @tentar="emit('tentar')"
        />
      </div>
      <p
        v-if="erroAoConferir"
        data-carteira="erro-nas-colunas"
        role="alert"
        class="m-0 text-base font-medium text-n-ruby-11"
      >
        {{ t(`${BASE}.COLUNAS.ERRO`) }}
      </p>
      <div class="flex flex-wrap items-center gap-3">
        <Button
          v-if="!conferidos"
          data-carteira="confirmar-colunas"
          size="lg"
          :label="
            t(
              erroAoConferir
                ? 'RELACIONAMENTOS.COMUM.TENTAR_DE_NOVO'
                : `${BASE}.COLUNAS.CERTO`
            )
          "
          :is-loading="conferindo"
          :aria-busy="conferindo"
          :disabled="ocupado"
          :aria-describedby="fraseDoQueFalta ? idDoAlerta : undefined"
          @click="confirmar"
        />
        <Button
          v-else-if="numeros.seguros === 0"
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
          :label="rotuloDoTrazer"
          :disabled="ocupado"
          @click="emit('trazer')"
        />
        <Button
          slate
          faded
          size="lg"
          data-carteira="voltar"
          :label="t('RELACIONAMENTOS.COMUM.VOLTAR')"
          :disabled="parado"
          @click="emit('voltar')"
        />
        <p
          data-carteira="relendo"
          role="status"
          class="m-0 text-base text-n-slate-11"
        >
          {{ fraseDoAndamento }}
        </p>
      </div>
    </div>
  </section>
</template>
