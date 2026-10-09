<script setup>
/*
 * Audit log messages are owned by the fork catalog and several action keys
 * are selected from the event mapping at runtime.
 */
/* eslint-disable @intlify/vue-i18n/no-missing-keys, @intlify/vue-i18n/no-dynamic-keys */

import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import {
  useStoreGetters,
  useStore,
  useMapGetter,
} from 'dashboard/composables/store';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import AuditLogFilters from './components/AuditLogFilters.vue';
import {
  generateTranslationPayload,
  generateLogActionKey,
  translateLogPayload,
  getAutonomiaOperationChanges,
  auditLogFiltersFromQuery,
  buildAuditLogRouteQuery,
} from 'dashboard/helper/auditlogHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const SEARCH_DEBOUNCE_DELAY = 500;
const MIN_SEARCH_LENGTH = 3;

const getters = useStoreGetters();
const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const records = computed(() => getters['auditlogs/getAuditLogs'].value);
const uiFlags = computed(() => getters['auditlogs/getUIFlags'].value);
const meta = computed(() => getters['auditlogs/getMeta'].value);
const humanAgentList = computed(() => getters['agents/getAgents']?.value || []);
const autonomiaAgentGetter = getters['autonomiaAgents/getRecords'];

const accountId = useMapGetter('getCurrentAccountId');
const currentAccount = useMapGetter('accounts/getAccount');
const globalConfig = useMapGetter('globalConfig/get');
const autonomiaAgentsEnabled = computed(() => {
  const account =
    typeof currentAccount.value === 'function'
      ? currentAccount.value(accountId.value)
      : null;

  return (
    globalConfig.value?.autonomiaAgentsEnabled === true &&
    account?.autonomia_agents_enabled === true
  );
});
const autonomiaAgentList = computed(() =>
  autonomiaAgentsEnabled.value ? autonomiaAgentGetter?.value || [] : []
);

const searchQuery = ref(route.query.q ?? '');
// The search term this page last put in the URL. Echoes of our own navigation
// must not overwrite a term the admin is still typing.
const pushedSearch = ref(searchQuery.value);

const filters = computed(() => auditLogFiltersFromQuery(route.query));

const hasActiveFilters = computed(() => {
  const {
    q,
    types,
    since,
    sort,
    agent_id: agentId,
    operation_key: operationKey,
  } = filters.value;
  return Boolean(q || types || since || sort || agentId || operationKey);
});

const fetchAuditLogs = async () => {
  try {
    await store.dispatch('auditlogs/fetch', filters.value);
  } catch (error) {
    const errorMessage = error?.message || t('AUDIT_LOGS.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  }
};

const fetchAutonomiaAgents = async () => {
  if (!autonomiaAgentsEnabled.value || !autonomiaAgentGetter) return;

  try {
    await store.dispatch('autonomiaAgents/get');
  } catch (error) {
    const errorMessage = error?.message || t('AUDIT_LOGS.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  }
};

const updateQuery = partial => {
  // a debounced search can land after the admin has moved to another page
  if (route.name !== 'auditlogs_list') return;
  router.push({
    name: 'auditlogs_list',
    query: buildAuditLogRouteQuery({ ...route.query, ...partial }),
  });
};

const onFiltersUpdate = partial => {
  updateQuery({ ...partial, page: undefined });
};

const onPageChange = page => {
  updateQuery({ page });
};

const clearFilters = () => {
  pushedSearch.value = '';
  searchQuery.value = '';
  router.push({ name: 'auditlogs_list', query: {} });
};

const generateLogText = auditLogItem => {
  const payload = generateTranslationPayload(
    auditLogItem,
    humanAgentList.value
  );
  const translationKey = generateLogActionKey(auditLogItem);
  const mergedPayload = translateLogPayload(payload, t);
  return t(translationKey, mergedPayload);
};

const operationChanges = auditLogItem =>
  getAutonomiaOperationChanges(auditLogItem);

const formatOperationValue = value => {
  if (value.type === 'empty') {
    return t('AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.EMPTY');
  }
  if (value.type === 'hidden') {
    return t('AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.HIDDEN');
  }
  if (value.type === 'boolean') {
    return t(
      value.value
        ? 'AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.ON'
        : 'AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.OFF'
    );
  }
  if (value.type === 'number') {
    return t('AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.SECONDS', {
      value: value.value,
    });
  }
  if (value.type === 'length') {
    return t('AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.LENGTH', {
      value: value.value,
    });
  }
  if (value.type === 'count') {
    return t('AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.COUNT', {
      value: value.value,
    });
  }
  if (value.type === 'range') {
    return t('AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.RANGE', {
      count: value.count,
      min: value.min,
      max: value.max,
    });
  }
  if (value.type === 'masked_list') {
    const preview = value.preview.join(', ');
    const remaining = value.count - value.preview.length;
    return remaining > 0
      ? t('AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.MASKED_LIST_MORE', {
          preview,
          remaining,
        })
      : t('AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.MASKED_LIST', { preview });
  }

  return t('AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.HIDDEN');
};

const formatOperationChange = change =>
  t('AUDIT_LOGS.AUTONOMIA_AGENT.CHANGE', {
    label: t(change.label),
    before: formatOperationValue(change.before),
    after: formatOperationValue(change.after),
  });

const showsRawIpAddress = computed(() =>
  getters['accounts/isFeatureEnabledonAccount'].value(
    getters.getCurrentAccountId.value,
    FEATURE_FLAGS.AUDIT_LOG_IP_ADDRESS
  )
);

const tableHeaders = computed(() => {
  return [
    t('AUDIT_LOGS.LIST.TABLE_HEADER.ACTIVITY'),
    t('AUDIT_LOGS.LIST.TABLE_HEADER.TIME'),
    showsRawIpAddress.value
      ? t('AUDIT_LOGS.LIST.TABLE_HEADER.IP_ADDRESS')
      : t('AUDIT_LOGS.LIST.TABLE_HEADER.LOCATION'),
  ];
});

const commitSearch = useDebounceFn(() => {
  const typed = searchQuery.value.trim();
  const term = typed.length < MIN_SEARCH_LENGTH ? '' : typed;
  if (term === pushedSearch.value) return;
  pushedSearch.value = term;
  onFiltersUpdate({ q: term || undefined });
}, SEARCH_DEBOUNCE_DELAY);

watch(searchQuery, () => commitSearch());

watch(
  () => route.query.q,
  value => {
    const next = value ?? '';
    if (next === pushedSearch.value) return;
    pushedSearch.value = next;
    searchQuery.value = next;
  }
);

watch(
  () => route.query,
  () => {
    if (route.name === 'auditlogs_list') fetchAuditLogs();
  }
);

onMounted(() => {
  store.dispatch('agents/get');
  fetchAutonomiaAgents();
  fetchAuditLogs();
});

watch(autonomiaAgentsEnabled, enabled => {
  if (enabled) fetchAutonomiaAgents();
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.fetchingList"
    :loading-message="$t('AUDIT_LOGS.LOADING')"
    :no-records-found="!records.length"
    :no-records-message="
      hasActiveFilters ? $t('AUDIT_LOGS.SEARCH_404') : $t('AUDIT_LOGS.LIST.404')
    "
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('AUDIT_LOGS.HEADER')"
        :description="$t('AUDIT_LOGS.DESCRIPTION')"
        :link-text="$t('AUDIT_LOGS.LEARN_MORE')"
        :search-placeholder="$t('AUDIT_LOGS.FILTERS.SEARCH_PLACEHOLDER')"
        feature-name="audit_logs"
      >
        <template #tabs>
          <AuditLogFilters
            :type="filters.types?.[0]"
            :range="route.query.range"
            :since="filters.since"
            :until="filters.until"
            :sort="filters.sort"
            :agent-id="filters.agent_id"
            :operation-key="filters.operation_key"
            :agents="autonomiaAgentList"
            @update="onFiltersUpdate"
          />
        </template>
        <template v-if="meta.totalEntries" #count>
          <span class="text-body-main text-n-slate-11 whitespace-nowrap">
            {{ $t('AUDIT_LOGS.COUNT', { n: meta.totalEntries }) }}
          </span>
        </template>
        <template v-if="hasActiveFilters" #actions>
          <Button
            :label="$t('AUDIT_LOGS.FILTERS.CLEAR_ALL')"
            icon="i-lucide-x"
            slate
            ghost
            sm
            @click="clearFilters"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <div class="flex flex-col">
        <BaseTable :headers="tableHeaders" :items="records">
          <template #row="{ items }">
            <BaseTableRow
              v-for="auditLogItem in items"
              :key="auditLogItem.id"
              :item="auditLogItem"
            >
              <template #default>
                <BaseTableCell>
                  <span
                    class="text-body-main text-n-slate-12 whitespace-nowrap"
                  >
                    {{ generateLogText(auditLogItem) }}
                  </span>
                  <ul
                    v-if="operationChanges(auditLogItem).length"
                    class="mt-1 flex flex-col gap-0.5 text-body-small text-n-slate-11"
                  >
                    <li
                      v-for="change in operationChanges(auditLogItem)"
                      :key="change.key"
                    >
                      {{ formatOperationChange(change) }}
                    </li>
                  </ul>
                </BaseTableCell>

                <BaseTableCell>
                  <span
                    class="text-body-main text-n-slate-11 whitespace-nowrap"
                  >
                    {{
                      messageTimestamp(
                        auditLogItem.created_at,
                        'MMM dd, yyyy hh:mm a'
                      )
                    }}
                  </span>
                </BaseTableCell>

                <BaseTableCell class="w-36">
                  <span class="text-body-main text-n-slate-11">
                    {{ auditLogItem.location || auditLogItem.remote_address }}
                  </span>
                </BaseTableCell>
              </template>
            </BaseTableRow>
          </template>
        </BaseTable>
        <PaginationFooter
          :current-page="Number(meta.currentPage)"
          :total-items="meta.totalEntries"
          :items-per-page="meta.perPage"
          class="!px-0"
          @update:current-page="onPageChange"
        />
      </div>
    </template>
  </SettingsLayout>
</template>
