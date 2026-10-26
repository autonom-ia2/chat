<script setup>
import { computed, ref } from 'vue';
import { rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import { usePodeAbrir } from 'dashboard/components-next/sidebar/fork/usePodeAbrir';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import ResultsToggle from 'dashboard/routes/dashboard/settings/booking/results/ResultsToggle.vue';
import CrmVistasNumeros from '../CrmVistasNumeros.vue';
import NumerosMes from './NumerosMes.vue';
import NumerosTopo from './NumerosTopo.vue';
import NumerosProximoPasso from './NumerosProximoPasso.vue';
import NumerosBloco from './NumerosBloco.vue';
import NumerosAjuda from './NumerosAjuda.vue';
import NumerosQuemCuidou from './NumerosQuemCuidou.vue';
import NumerosComoContamos from './NumerosComoContamos.vue';
import NumerosEspera from './NumerosEspera.vue';
import NumerosOrigensAtalho from './origens/NumerosOrigensAtalho.vue';
import { destinoDaEquipe } from './destinosEquipe';
import { P } from './numerosTextos';
import { useNumerosFormato } from './useNumerosFormato';
import { useNumerosDoMes } from './useNumerosDoMes';

// CRM › Números, visão "Equipe" (#1992, F5 do #1871), como no protótipo
// aprovado: topo, próximo passo (no máximo uma faixa amarela), Vendendo,
// Atendendo, "Quem precisa de ajuda" e o resto recolhido ("Quem cuidou", com a
// IA numa linha só). Os blocos seguem os funis que a pessoa vê no painel.
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
} = useNumerosDoMes({ t, locale, visao: 'equipe' });
const comoContamos = ref(null);

// "De onde vieram os clientes" (#2001, F6): o atalho só com a flag `crm_numeros_origens` da conta.
const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const origensLigada = computed(() =>
  Boolean(
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.CRM_NUMEROS_ORIGENS
    )
  )
);

const opcoesDeVisao = computed(() =>
  props.visoes.map(v => ({
    value: v,
    label: t(`${P}.VISAO.${v === 'eu' ? 'EU' : 'EQUIPE'}`),
  }))
);

const destinoDe = (tipo, opcoes = {}) =>
  destinoDaEquipe(tipo, {
    funis: dados.value.funis,
    fechado: dados.value.mes.fechado,
    podeAbrir,
    ...opcoes,
  });

const destinoDoTopo = computed(() => {
  const botao = dados.value?.topo?.botao;
  return botao ? destinoDe(botao.tipo) : null;
});

// Com mais de um agente ou robô no mês, a IA não tem um nome só: "A IA".
const proximo = computed(() =>
  (dados.value?.proximo || []).map(item =>
    item.tipo === 'ia_esperando' && !item.ia
      ? { ...item, ia: t(`${P}.IA_AJUDOU.IA`) }
      : item
  )
);
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
      class="mx-auto flex w-full max-w-3xl flex-col gap-5 px-4 pb-24 pt-5 sm:px-6 md:pb-5"
      data-numeros-v2
      data-numeros-visao-equipe
      :data-papel="dados?.papel"
    >
      <slot name="aviso" />
      <!-- Lugar do atalho "Metas do mês" da F4 (#1991): CrmNumerosPage põe o NumerosMetasAtalho aqui. -->
      <slot name="metas" />

      <div
        v-if="dados && !falhou && !dados.vazio"
        class="flex flex-wrap items-center justify-between gap-3"
      >
        <ResultsToggle
          v-if="opcoesDeVisao.length > 1"
          model-value="equipe"
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
        <Banner v-if="dados.leitura" color="slate" data-numeros-leitura>
          {{ t(`${P}.TOPO.LEITURA`) }}
        </Banner>
        <NumerosTopo
          :key="`topo-${dados.moeda}`"
          :topo="dados.topo"
          :mes="dados.mes"
          :mes-nome="mesNome"
          :rotulo-do-mes="rotuloDoMes"
          :moeda="dados.moeda"
          :destino="destinoDoTopo"
        />
        <NumerosProximoPasso :itens="proximo" :destino-de="destinoDe" />
        <NumerosBloco
          v-if="dados.vendendo"
          :key="`vendendo-${dados.moeda}`"
          tipo="vendendo"
          :bloco="dados.vendendo"
          :moeda="dados.moeda"
          :destino-de="destinoDe"
        />
        <!-- #2001 (F6): a porta para "De onde vieram os clientes". -->
        <NumerosOrigensAtalho
          v-if="dados.vendendo && origensLigada"
          :mes-chave="dados.mes.chave"
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
        <NumerosAjuda
          v-if="dados.ajuda.length"
          :itens="dados.ajuda"
          :destino-de="destinoDe"
        />
        <NumerosQuemCuidou
          :key="`cuidou-${dados.moeda}-${dados.mes.chave}`"
          :cuidou="dados.quemCuidou"
          :moeda="dados.moeda"
          :destino-de="destinoDe"
        />
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
  </div>
</template>
