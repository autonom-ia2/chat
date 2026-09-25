<script setup>
// Filtros do formulário de nova busca: um botão com a contagem e a gaveta
// lateral dos 4 grupos. Só o que for aplicado vai no pedido; fechar sem
// aplicar descarta o rascunho. O refino da busca aberta é outro estado.
import { computed, ref } from 'vue';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';
import { useI18n } from 'vue-i18n';
import FiltersBaseLine from './filters/FiltersBaseLine.vue';
import LeadFiltersPanel from './filters/LeadFiltersPanel.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import { activeAdvancedLeadFiltersCount } from '../../utils/advancedLeadFilters';
import { findPreset } from '../../utils/searchPresets';

const { t } = useI18n();
const { formFilters, form } = useProspectingSearchContext();

const isOpen = ref(false);
// A gaveta cobre o canto direito, onde fica o lançador do Guia (#646): sinaliza
// que está aberta para ele sair de cima do Aplicar.
useFixedPanelPresence(isOpen);
const activeCount = computed(() =>
  activeAdvancedLeadFiltersCount(formFilters.value)
);
const formPreset = computed(() => findPreset(form.value.preset_id));
const applyFilters = next => {
  formFilters.value = next;
  isOpen.value = false;
};
</script>

<template>
  <div class="rounded-md border border-n-weak bg-n-solid-2 px-3 py-2">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <button
        type="button"
        class="inline-flex min-h-11 items-center gap-2 text-sm font-semibold text-n-slate-12"
        @click="isOpen = true"
      >
        <span class="i-lucide-sliders-horizontal size-4" />
        {{ t('PROSPECTING.SEARCH.FILTER_DRAWER.OPEN') }}
      </button>
      <span
        v-if="activeCount"
        class="rounded-full bg-n-brand px-2 py-0.5 text-[11px] font-semibold text-white"
      >
        {{ t('PROSPECTING.SEARCH.ACTIVE_FILTERS', { count: activeCount }) }}
      </span>
    </div>
    <p class="mt-1 text-xs text-n-slate-10">
      {{ t('PROSPECTING.SEARCH.ADVANCED_FILTERS_HINT') }}
    </p>

    <div
      v-if="isOpen"
      class="fixed inset-0 z-40 bg-n-slate-12/30"
      @click.self="isOpen = false"
      @keydown.esc="isOpen = false"
    >
      <aside
        role="dialog"
        aria-modal="true"
        :aria-label="t('PROSPECTING.SEARCH.FILTER_DRAWER.TITLE')"
        class="ml-auto flex h-full w-full max-w-xl flex-col overflow-hidden border-l border-n-weak bg-n-solid-1 shadow-xl"
      >
        <header
          class="flex items-center justify-between gap-3 border-b border-n-weak px-5 py-4"
        >
          <div class="grid gap-1">
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ t('PROSPECTING.SEARCH.FILTER_DRAWER.TITLE') }}
            </h2>
            <FiltersBaseLine
              :preset="formPreset"
              :score-mode="form.score_mode"
            />
          </div>
          <button
            type="button"
            class="flex size-11 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-solid-2"
            :title="t('PROSPECTING.SEARCH.FILTER_DRAWER.CLOSE')"
            :aria-label="t('PROSPECTING.SEARCH.FILTER_DRAWER.CLOSE')"
            @click="isOpen = false"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </header>
        <div class="min-h-0 flex-1 overflow-y-auto p-5">
          <LeadFiltersPanel :filters="formFilters" @apply="applyFilters" />
        </div>
      </aside>
    </div>
  </div>
</template>
