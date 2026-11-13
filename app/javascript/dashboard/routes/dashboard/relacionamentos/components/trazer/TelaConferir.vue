<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import { partesDaFrase, planilhaApagada } from '../../trazer/contagem';
import { PERGUNTA_VALORES } from '../../trazer/respostas';
import { ERROS } from '../../trazer/useTrazerLista';
import { valoresRespondidos } from '../../trazer/valoresDeCliente';
import FichaDeExemplo from './FichaDeExemplo.vue';
import OQueVouGuardar from './OQueVouGuardar.vue';
import PrecisamDeVoce from './PrecisamDeVoce.vue';

// #2894 — "Conferir": a frase do que achei, três fichas de exemplo, o que
// precisa da pessoa, o que vai ser guardado e o botão único de trazer.
// #2896, Fatia 2 — junto do resumo, uma linha diz quantas linhas da planilha
// eram a mesma pessoa de outra e já foram juntadas (`resumo.juntadas`).
// E3: outra linha diz quantas das que entram vão entrar como cliente
// (`resumo.clientes`, conta do servidor); com zero, ela não aparece, a não ser
// que a pessoa tenha respondido quais valores querem dizer cliente: aí a linha
// diz que ninguém entra como cliente (a escolha não pegou ninguém). E o
// trazer que o servidor recusa por não haver ninguém para entrar
// (`recusaDoTrazer`) é dito como alerta, com o botão de trazer ligado.
// `total` é quantas pessoas entram, na conta do servidor. Com uma escrita em
// voo (`ocupado`) o Trazer e o Voltar ficam desligados, e o Trazer que a pessoa
// clicou fica carregando. `relendo`: a planilha está sendo lida de novo, dito
// num `status` junto dos botões. As linhas que precisam da pessoa vêm aos
// poucos (`faltamCarregar`, `carregandoMais`, `erroDoMais`, "Mostrar mais").
// A frase "Você pode desfazer quando quiser." só aparece quando a conta tem o
// desfazer (`temDesfazer`, que vem da fonte).
const props = defineProps({
  leitura: { type: Object, required: true },
  resumo: { type: Object, required: true },
  total: { type: Number, required: true },
  ocupado: { type: Boolean, default: false },
  relendo: { type: Boolean, default: false },
  comErro: { type: Boolean, default: false },
  // #2896 — o conserto que o servidor não aceitou: `{ linha, motivo }`.
  recusaDoConserto: { type: Object, default: null },
  // A troca de coluna que não deu certo: `{ coluna, chave }`.
  recusaDaColuna: { type: Object, default: null },
  // #2896 — o erro da tela (ERROS de trazer/useTrazerLista.js).
  recusaDoTrazer: { type: String, default: '' },
  faltamCarregar: { type: Number, default: 0 },
  carregandoMais: { type: Boolean, default: false },
  erroDoMais: { type: Boolean, default: false },
  temDesfazer: { type: Boolean, default: false },
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
const raiz = ref(null);
const ROTULOS_DO_CONTADOR = {
  NOVAS: 'RELACIONAMENTOS_TRAZER.CONFERIR.CONTADOR.NOVAS',
  COMPLETADAS: 'RELACIONAMENTOS_TRAZER.CONFERIR.CONTADOR.COMPLETADAS',
  PRECISAM: 'RELACIONAMENTOS_TRAZER.CONFERIR.CONTADOR.PRECISAM',
  DEIXADAS: 'RELACIONAMENTOS_TRAZER.CONFERIR.CONTADOR.DEIXADAS',
};

const semNinguemParaTrazer = computed(
  () => props.recusaDoTrazer === ERROS.NADA_PARA_TRAZER
);

// A pessoa disse quais valores querem dizer cliente e nenhuma das que entram
// tem um deles.
const escolhaSemClientes = computed(() => {
  const { perguntas = [], respostas = {} } = props.leitura;
  return (
    props.resumo.clientes === 0 &&
    perguntas.some(pergunta => pergunta.id === PERGUNTA_VALORES) &&
    valoresRespondidos(respostas[PERGUNTA_VALORES])
  );
});

// O Trazer que a pessoa clicou fica carregando até a escrita voltar.
const pediuParaTrazer = ref(false);
const trazer = () => {
  pediuParaTrazer.value = true;
  emit('trazer');
};
watch(
  () => props.ocupado,
  ocupado => {
    if (!ocupado) pediuParaTrazer.value = false;
  }
);

// "Achei 200 pessoas." — o título curto; os números vêm nos contadores.
const frase = computed(() =>
  t(
    'RELACIONAMENTOS_TRAZER.CONFERIR.FRASE.TOTAL',
    { count: props.resumo.total },
    props.resumo.total
  )
);

// Contador com zero não aparece. "Precisam de você" leva ao bloco dos problemas.
const contadores = computed(() =>
  partesDaFrase(props.resumo).map(({ chave, count }) => {
    const rotulo = t(ROTULOS_DO_CONTADOR[chave], count);
    return {
      chave,
      count,
      rotulo,
      leitura: `${count} ${rotulo}`,
      levaAosProblemas: chave === 'PRECISAM',
    };
  })
);

const irParaPrecisam = () => {
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
    data-relacionamentos="conferir"
    class="flex flex-col gap-10"
  >
    <div class="flex flex-col gap-6">
      <h1
        data-titulo-da-tela
        tabindex="-1"
        class="m-0 text-3xl font-bold leading-tight tracking-tight outline-none md:text-4xl text-n-slate-12"
      >
        {{ frase }}
      </h1>
      <ul
        v-if="contadores.length"
        data-relacionamentos="contadores"
        aria-live="polite"
        :aria-label="t('RELACIONAMENTOS_TRAZER.CONFERIR.CONTADOR.LISTA')"
        class="grid p-0 m-0 list-none gap-x-6 gap-y-4 md:flex md:flex-wrap md:gap-x-10"
        :class="contadores.length === 4 ? 'grid-cols-2' : 'grid-cols-3'"
      >
        <li
          v-for="contador in contadores"
          :key="contador.chave"
          :data-contador="contador.chave"
        >
          <component
            :is="contador.levaAosProblemas ? 'button' : 'div'"
            :type="contador.levaAosProblemas ? 'button' : undefined"
            class="flex flex-col items-start justify-start gap-1 p-0 m-0 bg-transparent border-0 min-h-11 text-start"
            :class="
              contador.levaAosProblemas
                ? 'rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand'
                : ''
            "
            @click="contador.levaAosProblemas ? irParaPrecisam() : undefined"
          >
            <span class="sr-only">{{ contador.leitura }}</span>
            <span
              class="text-4xl font-bold leading-none tabular-nums text-n-slate-12"
              aria-hidden="true"
            >
              {{ contador.count }}
            </span>
            <span
              class="text-sm text-n-slate-11"
              :class="
                contador.levaAosProblemas
                  ? 'underline underline-offset-4 decoration-n-weak'
                  : ''
              "
              aria-hidden="true"
            >
              {{ contador.rotulo }}
            </span>
          </component>
        </li>
      </ul>
      <p
        v-if="resumo.juntadas > 0"
        data-relacionamentos="juntadas"
        class="m-0 text-base text-n-slate-11"
      >
        {{
          t(
            'RELACIONAMENTOS_TRAZER.CONFERIR.JUNTADAS',
            { count: resumo.juntadas },
            resumo.juntadas
          )
        }}
      </p>
      <p
        v-if="resumo.clientes > 0"
        data-relacionamentos="entram-como-clientes"
        class="m-0 text-base text-n-slate-11"
      >
        {{
          t(
            'RELACIONAMENTOS_TRAZER.CONFERIR.CLIENTES',
            { count: resumo.clientes },
            resumo.clientes
          )
        }}
      </p>
      <p
        v-else-if="escolhaSemClientes"
        data-relacionamentos="entram-como-clientes"
        class="m-0 text-base text-n-slate-11"
      >
        {{ t('RELACIONAMENTOS_TRAZER.CONFERIR.SEM_CLIENTES') }}
      </p>
    </div>

    <section class="flex flex-col gap-4">
      <h2 class="m-0 text-2xl font-semibold tracking-tight text-n-slate-12">
        {{ t('RELACIONAMENTOS_TRAZER.CONFERIR.EXEMPLOS') }}
      </h2>
      <div class="grid gap-3 md:grid-cols-3">
        <FichaDeExemplo
          v-for="(pessoa, posicao) in leitura.exemplos"
          :key="posicao"
          :pessoa="pessoa"
        />
      </div>
    </section>

    <PrecisamDeVoce
      v-if="leitura.problemas.length || faltamCarregar > 0"
      :problemas="leitura.problemas"
      :ocupado="ocupado"
      :sem-conserto="planilhaApagada(leitura)"
      :recusa="recusaDoConserto"
      :faltam-carregar="faltamCarregar"
      :carregando-mais="carregandoMais"
      :erro-do-mais="erroDoMais"
      @mostrar-mais="emit('mostrarMais')"
      @guardar="(linha, valor) => emit('guardar', linha, valor)"
      @deixar-de-fora="linha => emit('deixarDeFora', linha)"
      @reabrir="linha => emit('reabrir', linha)"
    />

    <OQueVouGuardar
      :colunas="leitura.colunas"
      :ocupado="ocupado"
      :relendo="relendo"
      :recusa="recusaDaColuna"
      :tem-empresa="leitura.temEmpresa"
      @trocar="(...troca) => emit('trocar', ...troca)"
    />

    <div class="flex flex-col gap-4">
      <p
        v-if="total === 0"
        data-relacionamentos="ninguem-para-trazer"
        class="m-0 text-base font-medium text-n-slate-12"
      >
        {{ t('RELACIONAMENTOS_TRAZER.CONFERIR.NINGUEM') }}
      </p>
      <p
        v-else-if="temDesfazer"
        data-relacionamentos="conferir-sossego"
        class="flex items-center gap-2 m-0 text-base text-n-slate-11"
      >
        <span class="i-lucide-undo-2 size-5" aria-hidden="true" />
        {{ t('RELACIONAMENTOS_TRAZER.CONFERIR.SOSSEGO') }}
      </p>
      <p
        v-if="semNinguemParaTrazer"
        data-relacionamentos="recusa-do-trazer"
        role="alert"
        class="m-0 text-base font-medium text-n-ruby-11"
      >
        {{ t('RELACIONAMENTOS_TRAZER.ERROS.NADA_PARA_TRAZER') }}
      </p>
      <div v-if="comErro" data-relacionamentos="erro">
        <ErroComTentarDeNovo
          :mensagem="t('RELACIONAMENTOS_TRAZER.ERROS.TRAZER')"
          @tentar="emit('tentar')"
        />
      </div>
      <div class="flex flex-wrap items-center gap-3">
        <Button
          v-if="total === 0"
          data-relacionamentos="escolher-outra"
          size="lg"
          :label="t('RELACIONAMENTOS_TRAZER.CONFERIR.ESCOLHER_OUTRA')"
          :disabled="ocupado"
          @click="emit('escolherOutra')"
        />
        <Button
          v-else
          data-relacionamentos="trazer-confirmar"
          size="lg"
          :label="
            t('RELACIONAMENTOS_TRAZER.CONFERIR.TRAZER', { count: total }, total)
          "
          :disabled="ocupado"
          :is-loading="pediuParaTrazer && ocupado"
          @click="trazer"
        />
        <Button
          slate
          faded
          size="lg"
          :label="t('RELACIONAMENTOS.COMUM.VOLTAR')"
          :disabled="ocupado"
          @click="emit('voltar')"
        />
        <p
          data-relacionamentos="relendo"
          role="status"
          class="m-0 text-base text-n-slate-11"
        >
          {{ relendo ? t('RELACIONAMENTOS_TRAZER.CONFERIR.RELENDO') : '' }}
        </p>
      </div>
    </div>
  </section>
</template>
