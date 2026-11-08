<script setup>
// #2202 — o topo da lista com a chave lista_quem_espera: o título e dois botões com
// palavra, também no celular. "Recentes ▾" troca a ordem (3 opções; quem tinha outra
// guardada continua nela, com o nome dela no botão). "Filtrar ▾" troca o status num
// toque (Abertas, Resolvidas, Adiadas) ou abre o filtro avançado de hoje ("Mais
// filtros…"). Escolha única pelo ChoiceSelect do fork, nunca <select>.
// Com filtro avançado, pasta salva, escopo de contato ou filtro do link, o ChatList
// continua usando o ChatListHeader de sempre.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import wootConstants from 'dashboard/constants/globals';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

const props = defineProps({
  pageTitle: { type: String, required: true },
  activeStatus: { type: String, required: true },
  activeSortBy: { type: String, required: true },
  isOnExpandedLayout: { type: Boolean, default: false },
});

const emit = defineEmits(['basicFilterChange', 'filtersModal']);

const { t } = useI18n();
const store = useStore();
const { uiSettings, updateUISettings } = useUISettings();
const { STATUS_TYPE, SORT_BY_TYPE } = wootConstants;
const MAIS_FILTROS = 'mais_filtros';

const ORDENS = [
  { value: SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC, chave: 'RECENTES' },
  { value: SORT_BY_TYPE.WAITING_SINCE_ASC, chave: 'ESPERA' },
  { value: SORT_BY_TYPE.LAST_ACTIVITY_AT_ASC, chave: 'ANTIGAS' },
];

const opcoesDeOrdem = computed(() => {
  const lista = ORDENS.map(({ value, chave }) => ({
    value,
    label: t(`LISTA_DE_CONVERSAS.CABECALHO.${chave}`),
    shortLabel: t(`LISTA_DE_CONVERSAS.CABECALHO.${chave}_CURTO`),
  }));
  if (lista.some(opcao => opcao.value === props.activeSortBy)) return lista;
  // Ordem guardada de antes (ex.: Prioridade): continua valendo, com o nome dela.
  const nome = t(`CHAT_LIST.SORT_ORDER_ITEMS.${props.activeSortBy}.TEXT`);
  return [...lista, { value: props.activeSortBy, label: nome }];
});

const STATUS = [
  { value: STATUS_TYPE.OPEN, chave: 'ABERTAS' },
  { value: STATUS_TYPE.RESOLVED, chave: 'RESOLVIDAS' },
  { value: STATUS_TYPE.SNOOZED, chave: 'ADIADAS' },
];
const opcoesDeFiltro = computed(() => {
  const curto = t('LISTA_DE_CONVERSAS.CABECALHO.FILTRAR');
  return [
    ...STATUS.map(({ value, chave }) => ({
      value,
      label: t(`LISTA_DE_CONVERSAS.CABECALHO.${chave}`),
      shortLabel: curto,
    })),
    {
      value: MAIS_FILTROS,
      label: t('LISTA_DE_CONVERSAS.CABECALHO.MAIS_FILTROS'),
      shortLabel: curto,
    },
  ];
});

// O botão mostra "Filtrar" sempre; o status fora da lista (ex.: Pendentes, Todas,
// guardado de antes) também mostra "Filtrar".
const statusNoBotao = computed(() =>
  STATUS.some(item => item.value === props.activeStatus)
    ? props.activeStatus
    : ''
);

const guardar = (tipo, valor) => {
  const atual = uiSettings.value.conversations_filter_by || {};
  updateUISettings({
    conversations_filter_by: {
      status: tipo === 'status' ? valor : atual.status || props.activeStatus,
      order_by: tipo === 'sort' ? valor : atual.order_by || props.activeSortBy,
    },
  });
};

const mudarOrdem = valor => {
  if (valor === props.activeSortBy) return;
  emit('basicFilterChange', valor, 'sort');
  store.dispatch('setChatSortFilter', valor);
  guardar('sort', valor);
};

const mudarStatus = valor => {
  if (valor === MAIS_FILTROS) {
    emit('filtersModal');
    return;
  }
  if (valor === props.activeStatus) return;
  emit('basicFilterChange', valor, 'status');
  store.dispatch('setChatStatusFilter', valor);
  guardar('status', valor);
};

const voltarParaAbertas = () => mudarStatus(STATUS_TYPE.OPEN);

defineExpose({ voltarParaAbertas });
</script>

<template>
  <div class="flex flex-col gap-1 px-3 pt-2 pb-2" data-lista-cabecalho>
    <div class="flex items-center gap-1.5 min-h-11">
      <h1
        class="flex-1 min-w-0 m-0 text-base font-semibold truncate text-n-slate-12"
        :title="pageTitle"
      >
        {{ pageTitle }}
      </h1>
      <ChoiceSelect
        :model-value="activeSortBy"
        :options="opcoesDeOrdem"
        :aria-label="t('LISTA_DE_CONVERSAS.CABECALHO.ORDEM')"
        compact
        fit-selected
        class="flex-shrink-0"
        data-botao-ordem
        @update:model-value="mudarOrdem"
      />
      <div class="relative flex-shrink-0">
        <ChoiceSelect
          :model-value="statusNoBotao"
          :options="opcoesDeFiltro"
          :placeholder="t('LISTA_DE_CONVERSAS.CABECALHO.FILTRAR')"
          :aria-label="t('LISTA_DE_CONVERSAS.CABECALHO.FILTRAR_ARIA')"
          compact
          fit-selected
          data-botao-filtrar
          @update:model-value="mudarStatus"
        />
        <div
          id="conversationFilterTeleportTarget"
          class="absolute z-50 mt-2"
          :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
        />
      </div>
    </div>
    <p
      v-if="activeSortBy === 'waiting_since_asc'"
      class="m-0 text-xs text-n-slate-11"
      data-ajuda-da-ordem
    >
      {{ t('LISTA_DE_CONVERSAS.CABECALHO.AJUDA_ESPERA') }}
    </p>
  </div>
</template>
