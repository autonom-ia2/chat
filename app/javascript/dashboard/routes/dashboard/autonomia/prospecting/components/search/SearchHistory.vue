<script setup>
import { useI18n } from 'vue-i18n';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import * as formatters from '../../utils/searchFormatters';
import SearchPresetChip from './SearchPresetChip.vue';

const { t } = useI18n();
const {
  canManage,
  isLoading,
  isSearching,
  searches,
  searchHistoryMeta,
  selectedSearchId,
  deletingSearchId,
  canLoadMoreSearches,
  isLoadingMoreSearches,
  openSearch,
  openSearchConfig,
  deleteSearch,
  loadMoreSearches,
  repeatSearch,
  editSearch,
  findSearchPreset,
} = useProspectingSearchContext();

const formatSearchArea = search => formatters.formatSearchArea(search, t);
const formatRelativeTime = value => formatters.formatRelativeTime(value, t);
const searchPreset = search => findSearchPreset(search.preset_id);
</script>

<template>
  <aside
    class="flex min-h-0 flex-col overflow-hidden rounded-lg border border-n-weak bg-n-solid-1"
  >
    <div class="border-b border-n-weak px-4 py-3">
      <div class="flex items-baseline justify-between gap-3">
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ t('PROSPECTING.SEARCH.RECENT_SEARCHES') }}
        </h2>
        <span
          v-if="searchHistoryMeta.total_count"
          class="shrink-0 text-xs text-n-slate-10"
        >
          {{
            t('PROSPECTING.SEARCH.HISTORY_COUNT', {
              count: searchHistoryMeta.total_count,
            })
          }}
        </span>
      </div>
    </div>
    <!-- Carregando só enquanto não há lista: abrir uma busca não apaga o histórico. -->
    <div
      v-if="isLoading && !searches.length"
      class="px-4 py-8 text-sm text-n-slate-11"
    >
      {{ t('PROSPECTING.STATES.LOADING') }}
    </div>
    <div v-else-if="!searches.length" class="px-4 py-8 text-sm text-n-slate-11">
      {{ t('PROSPECTING.SEARCH.EMPTY') }}
    </div>
    <div v-else class="min-h-0 flex-1 overflow-y-auto p-3">
      <article
        v-for="search in searches"
        :key="search.id"
        class="relative mb-3 overflow-hidden rounded-md border border-n-weak bg-n-solid-1 transition last:mb-0 hover:border-n-slate-7 hover:bg-n-solid-2"
        :class="{
          'border-n-brand bg-n-brand-2 shadow-sm ring-1 ring-n-brand/30':
            selectedSearchId === search.id,
        }"
      >
        <span
          v-if="selectedSearchId === search.id"
          class="absolute inset-y-0 left-0 w-1 bg-n-brand"
        />
        <button
          type="button"
          class="grid min-w-0 w-full gap-2 overflow-hidden p-3 pl-4 text-left"
          @click="openSearch(search)"
        >
          <div
            class="grid min-w-0 grid-cols-[minmax(0,1fr)_auto] items-start gap-2 overflow-hidden"
          >
            <div class="min-w-0 overflow-hidden">
              <h3
                class="block w-full truncate text-sm font-semibold text-n-slate-12"
              >
                {{ search.query }}
              </h3>
              <p class="block w-full truncate text-xs text-n-slate-10">
                {{ `${search.location} · ${formatSearchArea(search)}` }}
              </p>
              <SearchPresetChip
                v-if="searchPreset(search)"
                class="mt-1"
                :preset="searchPreset(search)"
              />
            </div>
            <span
              class="shrink-0 rounded-md bg-n-solid-3 px-2 py-1 text-xs text-n-slate-11"
              :class="{
                'bg-n-brand text-white': selectedSearchId === search.id,
              }"
            >
              {{ search.results_count || 0 }}
            </span>
          </div>
          <div
            class="grid min-w-0 grid-cols-[minmax(0,1fr)_auto] items-center gap-2 overflow-hidden text-xs text-n-slate-10"
          >
            <span class="block min-w-0 truncate">
              {{
                t('PROSPECTING.SEARCH.RECENT_METRICS', {
                  leads: search.results_count || 0,
                  contacts: search.contact_count || 0,
                  crm: search.crm_count || 0,
                  score: search.average_score || '-',
                })
              }}
            </span>
            <span class="shrink-0">
              {{ formatRelativeTime(search.created_at) }}
            </span>
          </div>
        </button>
        <div
          v-if="canManage"
          class="flex flex-wrap items-center gap-2 border-t border-n-weak px-3 py-2.5"
        >
          <button
            type="button"
            class="inline-flex h-8 items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-1 px-2.5 text-xs font-medium text-n-slate-12 hover:bg-n-solid-2 disabled:cursor-wait disabled:opacity-60"
            :title="t('PROSPECTING.SEARCH.REPEAT_SEARCH')"
            :disabled="isSearching"
            @click.stop="repeatSearch(search)"
          >
            <span class="i-lucide-rotate-cw size-3.5" />
            {{ t('PROSPECTING.SEARCH.REPEAT_SEARCH') }}
          </button>
          <button
            type="button"
            class="inline-flex h-8 items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-1 px-2.5 text-xs font-medium text-n-slate-12 hover:bg-n-solid-2"
            :title="t('PROSPECTING.SEARCH.EDIT_SEARCH')"
            @click.stop="editSearch(search)"
          >
            <span class="i-lucide-pencil size-3.5" />
            {{ t('PROSPECTING.SEARCH.EDIT_SEARCH') }}
          </button>
          <button
            type="button"
            class="inline-flex h-8 items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-1 px-2.5 text-xs font-medium text-n-slate-12 hover:bg-n-solid-2"
            :title="t('PROSPECTING.SEARCH.CONFIGURE_SEARCH')"
            @click.stop="openSearchConfig(search)"
          >
            <span class="i-lucide-settings size-3.5" />
            {{ t('PROSPECTING.SEARCH.CONFIGURE_SEARCH') }}
          </button>
          <button
            type="button"
            class="inline-flex h-8 items-center gap-1.5 rounded-md border border-red-100 bg-red-50 px-2.5 text-xs font-medium text-red-700 hover:bg-red-100 disabled:cursor-not-allowed disabled:opacity-60"
            :title="t('PROSPECTING.SEARCH.DELETE_SEARCH')"
            :disabled="deletingSearchId === search.id"
            @click.stop="deleteSearch(search)"
          >
            <span class="i-lucide-trash-2 size-3.5" />
            {{ t('PROSPECTING.SEARCH.DELETE_SEARCH') }}
          </button>
        </div>
      </article>
      <button
        v-if="canLoadMoreSearches"
        type="button"
        class="mt-1 flex h-9 w-full items-center justify-center rounded-md border border-n-weak text-xs font-medium text-n-slate-11 hover:bg-n-solid-2 disabled:cursor-wait disabled:opacity-60"
        :disabled="isLoadingMoreSearches"
        @click="loadMoreSearches"
      >
        {{
          isLoadingMoreSearches
            ? t('PROSPECTING.SEARCH.LOADING_MORE')
            : t('PROSPECTING.SEARCH.LOAD_MORE')
        }}
      </button>
    </div>
  </aside>
</template>
