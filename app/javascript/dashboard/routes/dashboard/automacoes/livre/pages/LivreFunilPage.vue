<script setup>
import { computed, useId } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmKanbanCard from 'dashboard/routes/dashboard/crm/components/CrmKanbanCard.vue';
import LivreGaveta from '../components/LivreGaveta.vue';
import LivreEtapaPainel from '../components/LivreEtapaPainel.vue';
import LivreCartaoPainel from '../components/LivreCartaoPainel.vue';
import { CARTOES, ETAPAS, FUNIS } from '../prototipo/dados';
import { nomeDaEtapa } from '../prototipo/frases';
import { useAutomacoesLivre } from '../prototipo/useAutomacoesLivre';

// #2414 F0 — o Quadro do CRM de hoje (cabeçalho, colunas e o cartão de verdade,
// CrmKanbanCard), só para mostrar onde os painéis novos moram:
// "Automações desta etapa" no lugar das ações automáticas da etapa, em
// Configurar › Editar funil (`?etapa=`), e "Automações deste cartão" na gaveta
// do cartão (`?cartao=`).
const route = useRoute();
const router = useRouter();
const { automacoes, execucoesDoCartao } = useAutomacoesLivre();
const idEtapa = useId();

const etapaDe = id => ETAPAS.find(etapa => etapa.id === id);
const cartaoDe = id => CARTOES.find(cartao => cartao.id === Number(id));

const funilId = computed(
  () =>
    route.query.funil ||
    etapaDe(route.query.etapa)?.funil ||
    etapaDe(cartaoDe(route.query.cartao)?.etapa)?.funil ||
    'comercial'
);
const nomeDoFunil = computed(
  () => FUNIS.find(funil => funil.id === funilId.value)?.nome || ''
);
const opcoesDeFunil = FUNIS.map(funil => ({
  value: funil.id,
  label: funil.nome,
}));
const etapasDoFunil = computed(() =>
  ETAPAS.filter(etapa => etapa.funil === funilId.value)
);
const opcoesDeEtapa = computed(() =>
  etapasDoFunil.value.map(etapa => ({ value: etapa.id, label: etapa.nome }))
);

// O CrmKanbanCard recebe o cartão no formato da API do CRM.
const comoCardDoCrm = cartao => ({
  id: cartao.id,
  title: cartao.nome,
  value_cents: (cartao.valor || 0) * 100,
  currency: 'BRL',
  contact: { name: cartao.nome },
  responsible: { type: 'user', name: cartao.responsavel },
});

const colunas = computed(() =>
  etapasDoFunil.value.map(etapa => ({
    ...etapa,
    cartoes: CARTOES.filter(cartao => cartao.etapa === etapa.id),
  }))
);

const quantasNaEtapa = id =>
  automacoes.value.filter(
    item =>
      item.etapaAntiga === id || item.versao?.receita?.gatilho?.etapa === id
  ).length;

const cartaoAberto = computed(() => cartaoDe(route.query.cartao) || null);

const VISTAS = [
  { chave: 'CRM_LISTA_ACAO.VISTAS.QUADRO', icone: 'i-lucide-kanban' },
  { chave: 'CRM_KANBAN.VIEWS.LIST', icone: 'i-lucide-list' },
  { chave: 'CRM_KANBAN.VIEWS.CALENDAR', icone: 'i-lucide-calendar-days' },
  { chave: 'FORK_SIDEBAR.CRM.ABA_NUMEROS', icone: 'i-lucide-chart-column' },
];

const trocarQuery = mudanca => {
  const query = { ...route.query, ...mudanca };
  Object.keys(query).forEach(chave => {
    if (query[chave] === null) delete query[chave];
  });
  router.replace({ query });
};

const abrirConfigurar = () =>
  trocarQuery({ etapa: etapasDoFunil.value[0]?.id, cartao: null });

const temExecucao = cartao => execucoesDoCartao(cartao.id).length > 0;
</script>

<template>
  <main
    class="flex flex-col flex-1 w-full min-w-0 overflow-hidden bg-n-background"
  >
    <header
      class="flex flex-wrap items-center justify-between gap-3 px-6 py-3 border-b shrink-0 border-n-weak sm:px-8"
    >
      <div class="flex flex-wrap items-center min-w-0 gap-4">
        <h1 class="mb-0 text-2xl font-semibold text-n-slate-12">
          {{ $t('CRM_KANBAN.TITLE') }}
        </h1>
        <div
          class="flex flex-wrap items-center p-1 rounded-xl bg-n-alpha-2"
          role="presentation"
        >
          <span
            v-for="(vista, indice) in VISTAS"
            :key="vista.chave"
            class="inline-flex items-center gap-1.5 px-3 text-sm rounded-lg min-h-11"
            :class="
              indice === 0
                ? 'font-bold bg-n-surface-2 text-n-slate-12 shadow-sm'
                : 'font-medium text-n-slate-11'
            "
          >
            <span :class="vista.icone" class="size-3.5" aria-hidden="true" />
            {{ $t(vista.chave) }}
          </span>
        </div>
      </div>
      <Button
        data-configurar-funil
        :label="$t('CRM_KANBAN.ACTIONS.CONFIGURE')"
        icon="i-lucide-settings-2"
        slate
        outline
        class="!rounded-lg min-h-11 !outline-n-weak bg-n-surface-1"
        @click="abrirConfigurar"
      />
    </header>

    <div
      class="flex flex-wrap items-center gap-3 px-6 py-3 border-b shrink-0 border-n-weak sm:px-8"
    >
      <ChoiceSelect
        :model-value="funilId"
        :aria-label="$t('AUTOMACAO_LIVRE.FUNIL.QUAL')"
        :options="opcoesDeFunil"
        @update:model-value="
          funil => trocarQuery({ funil, etapa: null, cartao: null })
        "
      />
    </div>

    <section
      data-kanban-board
      class="flex flex-1 min-w-0 min-h-0 gap-4 px-8 py-5 pb-40 overflow-x-auto bg-n-slate-3"
    >
      <article
        v-for="coluna in colunas"
        :key="coluna.id"
        :data-coluna="coluna.id"
        class="flex h-full w-[19rem] shrink-0 flex-col overflow-hidden rounded-xl bg-n-alpha-1"
      >
        <header
          class="flex items-center justify-between gap-3 px-4 py-3 min-h-14"
        >
          <div class="flex items-center min-w-0 gap-2">
            <span class="size-2.5 shrink-0 rounded-sm bg-[#64748b]" />
            <h2 class="mb-0 text-base font-semibold truncate text-n-slate-12">
              {{ coluna.nome }}
            </h2>
          </div>
          <span
            class="px-2 py-1 text-xs font-medium rounded-lg shrink-0 bg-n-surface-1 tabular-nums text-n-slate-11"
          >
            {{ coluna.cartoes.length }}
          </span>
        </header>
        <div
          class="flex flex-col flex-1 min-h-0 gap-3 px-2 pt-2 pb-3 overflow-y-auto"
        >
          <div
            v-for="cartao in coluna.cartoes"
            :key="cartao.id"
            :data-cartao="cartao.id"
            class="flex flex-col w-full gap-1.5 shrink-0"
          >
            <CrmKanbanCard
              :card="comoCardDoCrm(cartao)"
              com-valor
              @open="trocarQuery({ cartao: String(cartao.id), etapa: null })"
            />
            <span
              v-if="temExecucao(cartao)"
              data-cartao-com-automacao
              class="inline-flex items-center self-start gap-1 px-2.5 py-1 text-xs font-semibold rounded-full ms-2 bg-n-blue-3 text-n-blue-11"
            >
              <span class="i-lucide-zap size-3" aria-hidden="true" />
              {{ $t('AUTOMACAO_LIVRE.FUNIL.SELO') }}
            </span>
          </div>
        </div>
      </article>
    </section>

    <LivreGaveta
      :aberta="Boolean(route.query.etapa)"
      :rotulo="$t('CRM_KANBAN.ACTIONS.EDIT_PIPELINE')"
      :titulo="nomeDoFunil"
      :texto="$t('AUTOMACAO_LIVRE.FUNIL.GAVETA_ETAPA')"
      :migalha="$t('AUTOMACAO_LIVRE.FUNIL.FUNIS_DO_CRM')"
      @fechar="trocarQuery({ etapa: null })"
    >
      <div
        v-if="route.query.etapa"
        class="flex flex-col w-full max-w-3xl gap-5 px-5 py-6 sm:px-8"
      >
        <div class="flex flex-col gap-1.5">
          <label :for="idEtapa" class="text-sm font-medium text-n-slate-12">
            {{ $t('AUTOMACAO_LIVRE.FUNIL.ETAPA') }}
          </label>
          <ChoiceSelect
            :model-value="route.query.etapa"
            :trigger-id="idEtapa"
            :aria-label="$t('AUTOMACAO_LIVRE.FUNIL.ETAPA')"
            :options="opcoesDeEtapa"
            @update:model-value="etapa => trocarQuery({ etapa })"
          />
        </div>
        <article
          class="flex flex-col gap-4 p-4 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 sm:p-5"
        >
          <div class="flex items-center gap-3">
            <span
              class="grid rounded-xl place-items-center size-12 shrink-0 bg-n-iris-3 text-n-iris-11"
            >
              <span class="i-lucide-zap size-6" aria-hidden="true" />
            </span>
            <h3 class="mb-0 text-base font-semibold text-n-slate-12">
              {{
                $t('AUTOMACAO_LIVRE.ETAPA.TITULO', {
                  etapa: nomeDaEtapa(route.query.etapa),
                })
              }}
              <span
                class="px-2 py-0.5 ms-1 text-xs font-medium rounded-lg bg-n-alpha-2 tabular-nums text-n-slate-11"
              >
                {{ quantasNaEtapa(route.query.etapa) }}
              </span>
            </h3>
          </div>
          <LivreEtapaPainel :etapa-id="route.query.etapa" />
        </article>
      </div>
    </LivreGaveta>

    <LivreGaveta
      :aberta="Boolean(cartaoAberto)"
      :rotulo="cartaoAberto ? nomeDaEtapa(cartaoAberto.etapa) : ''"
      icone="i-lucide-columns-3"
      :titulo="cartaoAberto?.nome || ''"
      :texto="$t('AUTOMACAO_LIVRE.FUNIL.GAVETA_CARTAO')"
      :migalha="nomeDoFunil"
      @fechar="trocarQuery({ cartao: null })"
    >
      <div
        v-if="cartaoAberto"
        class="flex flex-col w-full max-w-3xl gap-5 px-5 py-6 sm:px-8"
      >
        <LivreCartaoPainel :cartao-id="cartaoAberto.id" />
      </div>
    </LivreGaveta>
  </main>
</template>
