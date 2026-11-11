<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../../comum/ErroComTentarDeNovo.vue';
import OQueVouGuardar from '../../trazer/OQueVouGuardar.vue';
import ContadoresDosSeguros from './ContadoresDosSeguros.vue';
import ExemplosComSeguros from './ExemplosComSeguros.vue';
import PrecisamDosSeguros from './PrecisamDosSeguros.vue';
import { CHAVES_DOS_DESTINOS_DE_SEGURO } from '../../../carteira/destinosDeSeguro';
import { COMO } from '../../../carteira/passosDeTrazerSeguros';

// #2897 — "Conferir" dos seguros, igual para a planilha, os PDFs e o Agger: a
// frase do que achei, os contadores, o que acontece amanhã cedo, o que precisa
// da pessoa, as fichas de exemplo, o que não é apólice e o que vou guardar. O
// botão único de trazer (que sobe a cada problema resolvido), o Voltar e a
// frase do desfazer ficam numa barra sempre à vista, no fim da área de conteúdo.
const props = defineProps({
  leitura: { type: Object, required: true },
  contadores: { type: Array, required: true },
  total: { type: Number, required: true },
  ocupado: { type: Boolean, default: false },
  comErro: { type: Boolean, default: false },
});
const emit = defineEmits([
  'guardar',
  'deixarDeFora',
  'reabrir',
  'trocar',
  'trazer',
  'voltar',
  'tentar',
]);

const { t } = useI18n();
const tc = (chave, ...resto) =>
  t(`RELACIONAMENTOS_CARTEIRA.TRAZER.CONFERIR.${chave}`, ...resto);
const raiz = ref(null);

// As marcas de cada jeito de trazer, para o roteiro dos prints.
const MARCAS = {
  [COMO.PLANILHA]: { tela: 'planilha-conferir', botao: 'trazer-seguros' },
  [COMO.PDFS]: {
    tela: 'pdfs-conferir',
    botao: 'trazer-pdfs',
    precisam: 'pdfs-precisam',
  },
  [COMO.AGGER]: { tela: 'agger-conferir', botao: 'trazer-agger' },
};
const marcas = computed(() => MARCAS[props.leitura.origem]);

// "Li 40 PDFs. Achei 39 seguros de 31 pessoas."
const frase = computed(() => {
  const { pdfs, seguros, pessoas } = props.leitura.achei;
  return [
    pdfs ? tc('LI_PDFS', { count: pdfs }, pdfs) : '',
    tc('ACHEI_SEGUROS', { count: seguros }, seguros),
    tc('DE_PESSOAS', { count: pessoas }, pessoas),
  ]
    .filter(Boolean)
    .join(' ');
});

const efeito = computed(() => {
  const { dias, seguros } = props.leitura.efeito;
  return seguros > 0 ? tc('EFEITO', { count: seguros, dias }, seguros) : '';
});

const destinosDeSeguro = computed(() =>
  Object.entries(CHAVES_DOS_DESTINOS_DE_SEGURO).map(([value, chave]) => ({
    value,
    label: t(chave),
  }))
);

const irParaPrecisam = () => {
  const secao = raiz.value?.querySelector(
    '[data-relacionamentos="precisam-de-voce"]'
  );
  if (!secao) return;
  const semMovimento = window.matchMedia?.(
    '(prefers-reduced-motion: reduce)'
  )?.matches;
  secao.scrollIntoView({
    behavior: semMovimento ? 'auto' : 'smooth',
    block: 'start',
  });
  secao
    .querySelector('[data-relacionamentos="precisam-titulo"]')
    ?.focus({ preventScroll: true });
};
</script>

<template>
  <section
    ref="raiz"
    data-relacionamentos="conferir"
    :data-carteira="marcas.tela"
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
      <ContadoresDosSeguros
        :contadores="contadores"
        @precisam="irParaPrecisam"
      />
      <p
        v-if="leitura.semTelefone"
        data-carteira="sem-telefone-apoio"
        class="m-0 text-base text-n-slate-11"
      >
        {{ tc('SEM_TELEFONE_APOIO') }}
      </p>
      <p
        v-if="efeito"
        data-carteira="efeito-renovacao"
        class="flex items-start gap-2 m-0 text-base text-n-slate-12"
      >
        <span
          class="i-lucide-calendar-clock size-5 shrink-0 mt-0.5 text-n-blue-11"
          aria-hidden="true"
        />
        {{ efeito }}
      </p>
    </div>

    <PrecisamDosSeguros
      v-if="leitura.problemas.length"
      :problemas="leitura.problemas"
      :seguradoras="leitura.seguradoras"
      :ocupado="ocupado"
      :marca="marcas.precisam"
      @guardar="(linha, valor) => emit('guardar', linha, valor)"
      @deixar-de-fora="linha => emit('deixarDeFora', linha)"
      @reabrir="linha => emit('reabrir', linha)"
    />

    <ExemplosComSeguros
      v-if="leitura.exemplos.length"
      :exemplos="leitura.exemplos"
    />

    <section
      v-if="leitura.naoEApolice.length"
      data-carteira="pdfs-nao-e-apolice"
      class="flex flex-col gap-3"
    >
      <h2 class="m-0 text-2xl font-semibold tracking-tight text-n-slate-12">
        {{ tc('NAO_E_APOLICE_TITULO', { count: leitura.naoEApolice.length }) }}
      </h2>
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="arquivo in leitura.naoEApolice"
          :key="arquivo"
          class="text-base break-words text-n-slate-11"
        >
          {{ tc('NAO_E_APOLICE', { arquivo }) }}
        </li>
      </ul>
    </section>

    <OQueVouGuardar
      v-if="leitura.colunas.length"
      :colunas="leitura.colunas"
      :ocupado="ocupado"
      :destinos-a-mais="destinosDeSeguro"
      @trocar="(coluna, destino) => emit('trocar', coluna, destino)"
    />

    <div v-if="comErro" data-carteira="erro">
      <ErroComTentarDeNovo
        :mensagem="tc('ERRO_TRAZER')"
        @tentar="emit('tentar')"
      />
    </div>

    <!-- A ação principal fica sempre à vista: a barra gruda no fim da área de
         conteúdo. Ela ocupa lugar na página (não flutua por cima), então o
         último bloco nunca fica coberto. Abaixo de `md` o conteúdo começa
         depois do canto do botão ☰ do app (`ps-20`, como o rodapé dos
         ajustes e a barra de ação da lista). -->
    <div
      data-carteira="barra-de-trazer"
      class="sticky bottom-0 z-20 flex flex-wrap items-center gap-x-4 gap-y-3 ps-20 pe-5 pt-4 -mx-5 border-t md:-mx-8 md:ps-8 md:pe-8 border-n-weak bg-n-surface-1 pb-[calc(1rem+env(safe-area-inset-bottom))]"
    >
      <Button
        :data-carteira="marcas.botao"
        size="lg"
        class="flex-1 sm:flex-none"
        :label="tc('TRAZER', { count: total }, total)"
        :disabled="ocupado"
        @click="emit('trazer')"
      />
      <Button
        slate
        faded
        size="lg"
        data-carteira="voltar-do-conferir"
        :label="t('RELACIONAMENTOS.COMUM.VOLTAR')"
        @click="emit('voltar')"
      />
      <p
        data-carteira="sossego"
        class="flex items-center gap-2 m-0 text-sm basis-full sm:basis-auto text-n-slate-11"
      >
        <span class="i-lucide-undo-2 size-4 shrink-0" aria-hidden="true" />
        {{ tc('SOSSEGO') }}
      </p>
    </div>
  </section>
</template>
