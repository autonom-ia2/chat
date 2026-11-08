<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { usePodeAbrir } from 'dashboard/components-next/sidebar/fork/usePodeAbrir';
import { ROTA_NUMEROS, useAbaNumeros } from './useAbaNumeros';

// Na página Números (#1617), o mesmo seletor do CRM para voltar ao Kanban, à Lista ou ao Calendário.
// Lista e Calendário abrem o CRM já na vista certa (`?view=`).
const { t } = useI18n();
const { mostrar } = useAbaNumeros();
const { podeAbrir } = usePodeAbrir();
const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
// #2283: com a Lista nova, "Quadro", como no seletor da página do CRM.
const listaAcaoLigada = computed(() =>
  Boolean(
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.CRM_LISTA_ACAO
    )
  )
);

// Quem só vê os relatórios do CRM (crm_view_reports sem crm_view) não ganha link para tela que não abre.
const vistas = computed(() =>
  [
    {
      id: 'kanban',
      to: { name: 'crm_kanban_index' },
      label: listaAcaoLigada.value
        ? t('CRM_LISTA_ACAO.VISTAS.QUADRO')
        : t('CRM_KANBAN.VIEWS.KANBAN'),
      icon: 'i-lucide-kanban',
    },
    {
      id: 'list',
      to: { name: 'crm_kanban_index', query: { view: 'list' } },
      label: t('CRM_KANBAN.VIEWS.LIST'),
      icon: 'i-lucide-list',
    },
    {
      id: 'calendar',
      to: { name: 'crm_kanban_index', query: { view: 'calendar' } },
      label: t('CRM_KANBAN.VIEWS.CALENDAR'),
      icon: 'i-lucide-calendar-days',
    },
  ].filter(vista => podeAbrir(vista.to))
);
</script>

<template>
  <nav
    v-if="mostrar"
    data-vistas-numeros
    class="flex flex-wrap items-center rounded-xl bg-n-alpha-2 p-1"
    :aria-label="t('FORK_SIDEBAR.CRM.VISTAS')"
  >
    <RouterLink
      v-for="vista in vistas"
      :key="vista.id"
      :to="vista.to"
      class="inline-flex min-h-11 items-center gap-1.5 rounded-lg px-3 text-sm font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand motion-reduce:transition-none"
    >
      <span :class="vista.icon" class="size-3.5" aria-hidden="true" />
      {{ vista.label }}
    </RouterLink>
    <RouterLink
      :to="{ name: ROTA_NUMEROS }"
      aria-current="page"
      class="inline-flex min-h-11 items-center gap-1.5 rounded-lg px-3 text-sm !font-bold bg-n-surface-2 text-n-slate-12 shadow-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    >
      <span class="i-lucide-chart-column size-3.5" aria-hidden="true" />
      {{ t('FORK_SIDEBAR.CRM.ABA_NUMEROS') }}
    </RouterLink>
  </nav>
  <template v-else />
</template>
