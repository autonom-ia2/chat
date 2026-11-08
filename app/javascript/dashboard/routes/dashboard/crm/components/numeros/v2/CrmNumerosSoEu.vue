<script setup>
import { computed, ref } from 'vue';
import { rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import { usePodeAbrir } from 'dashboard/components-next/sidebar/fork/usePodeAbrir';
import ResultsToggle from 'dashboard/routes/dashboard/settings/booking/results/ResultsToggle.vue';
import CrmVistasNumeros from '../CrmVistasNumeros.vue';
import NumerosMes from './NumerosMes.vue';
import NumerosTopo from './NumerosTopo.vue';
import NumerosProximoPasso from './NumerosProximoPasso.vue';
import NumerosBloco from './NumerosBloco.vue';
import NumerosIaAjudou from './NumerosIaAjudou.vue';
import NumerosComoContamos from './NumerosComoContamos.vue';
import NumerosEspera from './NumerosEspera.vue';
import NumerosMetasGaveta from './NumerosMetasGaveta.vue';
import { usePodeDefinirMetas } from './usePodeDefinirMetas';
import { destino } from './destinos';
import { larguraDe } from './barras';
import { P } from './numerosTextos';
import { useNumerosFormato } from './useNumerosFormato';
import { useNumerosDoMes } from './useNumerosDoMes';

// CRM › Números, visão "Só eu" (#1897, F3 do #1871), como no protótipo
// aprovado: topo, próximo passo, Vendendo e/ou Atendendo (o papel vem do tipo
// do funil), "A IA te ajudou" e a barra da equipe, sem nomes.
const props = defineProps({
  visoes: { type: Array, required: true },
});
const emit = defineEmits(['visao']);

const { podeAbrir } = usePodeAbrir();
const { t, locale } = useNumerosFormato();
const {
  dados,
  carregando,
  falhou,
  carregar,
  irParaMes,
  fuso,
  nomeMes,
  mesNome,
  rotuloDoMes,
} = useNumerosDoMes({ t, locale });
const comoContamos = ref(null);
// #1991: quem define as metas abre a gaveta pelo topo; salvar recarrega a tela.
const podeDefinirMetas = usePodeDefinirMetas();
const gavetaMetas = ref(null);

const opcoesDeVisao = computed(() =>
  props.visoes.map(v => ({
    value: v,
    label: t(`${P}.VISAO.${v === 'eu' ? 'EU' : 'EQUIPE'}`),
  }))
);

const destinoDe = (tipo, opcoes = {}) =>
  destino(tipo, {
    funis: dados.value.funis,
    fechado: dados.value.mes.fechado,
    podeAbrir,
    ...opcoes,
  });

const destinoDoTopo = computed(() => {
  const botao = dados.value?.topo?.botao;
  return botao ? destinoDe(botao.tipo) : null;
});
</script>

<template>
  <div class="flex h-full w-full flex-col overflow-auto bg-n-background">
    <header
      class="flex flex-col gap-3 border-b border-n-weak px-4 py-4 sm:px-6 sm:py-5"
    >
      <div class="flex flex-wrap items-center gap-4">
        <h1 class="m-0 text-xl font-semibold text-n-slate-12">
          {{ t(`${P}.TITULO`) }}
        </h1>
        <CrmVistasNumeros />
      </div>
    </header>

    <main
      class="mx-auto flex w-full max-w-3xl flex-col gap-5 px-4 py-5 sm:px-6"
      data-numeros-v2
      :data-papel="dados?.papel"
    >
      <slot name="aviso" />

      <div
        v-if="dados && !falhou && !dados.vazio"
        class="flex flex-wrap items-center justify-between gap-3"
      >
        <ResultsToggle
          v-if="opcoesDeVisao.length > 1"
          model-value="eu"
          :options="opcoesDeVisao"
          :label="t(`${P}.VISAO.ROTULO`)"
          :disabled="carregando"
          data-numeros-visao
          @update:model-value="valor => emit('visao', valor)"
        />
        <NumerosMes
          :rotulo="mesNome"
          :anterior="nomeMes(dados.mes.anterior)"
          :seguinte="nomeMes(dados.mes.seguinte)"
          :disabled="carregando"
          @anterior="irParaMes(dados.mes.anterior)"
          @seguinte="irParaMes(dados.mes.seguinte)"
        />
      </div>

      <NumerosEspera
        v-if="(carregando && !dados) || falhou"
        :falhou="falhou"
        @tentar="carregar"
      />

      <div
        v-else-if="dados?.vazio"
        data-numeros-vazio
        class="flex flex-col items-center gap-4 rounded-2xl bg-n-solid-1 px-6 py-10 text-center ring-1 ring-inset ring-n-weak"
      >
        <p class="m-0 text-lg font-semibold text-n-slate-12">
          {{ t(`${P}.VAZIO.TITULO`) }}
        </p>
        <p class="m-0 text-sm text-n-slate-11">
          {{
            dados.podeCriarFunil
              ? t(`${P}.VAZIO.TEXTO`)
              : t(`${P}.VAZIO.SEM_PODER`)
          }}
        </p>
        <RouterLink
          v-if="dados.podeCriarFunil"
          :to="{ name: 'crm_kanban_index' }"
          class="inline-flex min-h-12 items-center rounded-xl bg-n-blue-9 px-6 text-base font-semibold text-white hover:bg-n-blue-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ t(`${P}.VAZIO.ACAO`) }}
        </RouterLink>
      </div>

      <template v-else-if="dados">
        <NumerosTopo
          :key="`topo-${dados.moeda}`"
          :topo="dados.topo"
          :mes="dados.mes"
          :mes-nome="mesNome"
          :rotulo-do-mes="rotuloDoMes"
          :moeda="dados.moeda"
          :destino="destinoDoTopo"
          :pode-definir-metas="podeDefinirMetas && !dados.mes.fechado"
          @metas="gavetaMetas?.abrir()"
        />
        <NumerosProximoPasso :itens="dados.proximo" :destino-de="destinoDe" />
        <NumerosBloco
          v-if="dados.vendendo"
          :key="`vendendo-${dados.moeda}`"
          tipo="vendendo"
          :bloco="dados.vendendo"
          :moeda="dados.moeda"
          :destino-de="destinoDe"
        />
        <NumerosBloco
          v-if="dados.atendendo"
          tipo="atendendo"
          :bloco="dados.atendendo"
          :moeda="dados.moeda"
          :destino-de="destinoDe"
        />
        <p
          v-if="dados.estimado"
          data-numeros-estimado
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t(`${P}.ESTIMADO`) }}
        </p>
        <NumerosIaAjudou
          v-if="dados.iaAjudou"
          :ajuda="dados.iaAjudou"
          :destino="destinoDe('ia_passou')"
        />
        <section
          v-if="dados.equipePct !== null"
          data-numeros-equipe
          class="flex flex-col gap-2 rounded-xl bg-n-solid-1 px-4 py-3 ring-1 ring-inset ring-n-weak"
        >
          <p class="mb-0 text-sm text-n-slate-12">
            {{ t(`${P}.EQUIPE_BARRA`, { pct: dados.equipePct }) }}
          </p>
          <span
            aria-hidden="true"
            class="block h-1.5 w-full overflow-hidden rounded-full bg-n-alpha-2"
          >
            <span
              class="block h-full rounded-full bg-n-slate-9"
              :class="larguraDe(dados.equipePct)"
            />
          </span>
        </section>
        <button
          type="button"
          data-como-contamos-link
          class="inline-flex min-h-11 w-fit items-center gap-1.5 rounded-xl px-3 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="comoContamos?.abrir()"
        >
          <span class="i-lucide-circle-help size-4" aria-hidden="true" />
          {{ t(`${P}.COMO_CONTAMOS.LINK`) }}
        </button>
      </template>
    </main>

    <NumerosComoContamos ref="comoContamos" :fuso="rotuloDoFuso(fuso)" />
    <NumerosMetasGaveta
      v-if="podeDefinirMetas"
      ref="gavetaMetas"
      @salvo="carregar"
    />
  </div>
</template>
