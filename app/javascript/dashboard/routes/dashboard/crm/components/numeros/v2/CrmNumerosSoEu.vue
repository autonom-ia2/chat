<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { fusoDaConta, rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import { usePodeAbrir } from 'dashboard/components-next/sidebar/fork/usePodeAbrir';
import CrmNumerosAPI from 'dashboard/api/crmNumeros';
import ResultsToggle from 'dashboard/routes/dashboard/settings/booking/results/ResultsToggle.vue';
import CrmVistasNumeros from '../CrmVistasNumeros.vue';
import NumerosMes from './NumerosMes.vue';
import NumerosTopo from './NumerosTopo.vue';
import NumerosProximoPasso from './NumerosProximoPasso.vue';
import NumerosBloco from './NumerosBloco.vue';
import NumerosIaAjudou from './NumerosIaAjudou.vue';
import NumerosComoContamos from './NumerosComoContamos.vue';
import { destino } from './destinos';
import { P, comMaiuscula, nomeDoMes } from './numerosTextos';
import { useNumerosFormato } from './useNumerosFormato';

// CRM › Números, visão "Só eu" (#1897, F3 do #1871), como no protótipo
// aprovado: topo, próximo passo, Vendendo e/ou Atendendo (o papel vem do tipo
// do funil), "A IA te ajudou" e a barra da equipe, sem nomes. O mês vem do
// endereço (?mes=AAAA-MM).
const props = defineProps({
  visoes: { type: Array, required: true },
});
const emit = defineEmits(['visao']);

const route = useRoute();
const router = useRouter();
const { currentAccount } = useAccount();
const { podeAbrir } = usePodeAbrir();
const { t, locale } = useNumerosFormato();

const dados = ref(null);
const carregando = ref(true);
const falhou = ref(false);
const comoContamos = ref(null);

const mes = computed(() => route.query.mes || undefined);

const carregar = async () => {
  carregando.value = true;
  falhou.value = false;
  try {
    const { data } = await CrmNumerosAPI.show({ mes: mes.value });
    dados.value = data;
  } catch {
    falhou.value = true;
  } finally {
    carregando.value = false;
  }
};
watch(mes, carregar, { immediate: true });

const irParaMes = chave =>
  router.replace({ query: { ...route.query, mes: chave } });

const fuso = computed(() => fusoDaConta(currentAccount.value));
const nomeMes = chave =>
  chave ? nomeDoMes(chave, { locale: locale(), fuso: fuso.value }) : '';
const mesNome = computed(() => nomeMes(dados.value?.mes?.chave));
const rotuloDoMes = computed(() => {
  const info = dados.value?.mes;
  if (!info) return '';
  const nome = comMaiuscula(mesNome.value);
  return info.fechado
    ? t(`${P}.MES.FECHADO`, { mes: nome })
    : t(
        `${P}.MES.ATUAL`,
        { mes: nome, n: info.diasRestantes },
        info.diasRestantes
      );
});

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

      <div
        v-if="carregando && !dados"
        aria-busy="true"
        data-numeros-carregando
        class="flex flex-col gap-3"
      >
        <span class="sr-only">{{ t(`${P}.CARREGANDO`) }}</span>
        <div class="h-48 animate-pulse rounded-2xl bg-n-alpha-2" />
        <div class="h-24 animate-pulse rounded-2xl bg-n-alpha-2" />
      </div>

      <div
        v-else-if="falhou"
        role="alert"
        data-numeros-erro
        class="flex flex-col items-start gap-4 rounded-2xl bg-n-ruby-2 p-6 ring-1 ring-inset ring-n-ruby-6"
      >
        <p class="m-0 text-base text-n-ruby-12">{{ t(`${P}.ERRO.TEXTO`) }}</p>
        <button
          type="button"
          class="inline-flex min-h-11 items-center rounded-xl bg-n-ruby-9 px-5 text-base font-semibold text-white hover:bg-n-ruby-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="carregar"
        >
          {{ t(`${P}.ERRO.ACAO`) }}
        </button>
      </div>

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
          :topo="dados.topo"
          :mes="dados.mes"
          :mes-nome="mesNome"
          :rotulo-do-mes="rotuloDoMes"
          :moeda="dados.moeda"
          :destino="destinoDoTopo"
        />
        <NumerosProximoPasso :itens="dados.proximo" :destino-de="destinoDe" />
        <NumerosBloco
          v-if="dados.vendendo"
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
              :style="{ width: `${Math.min(100, dados.equipePct)}%` }"
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
  </div>
</template>
