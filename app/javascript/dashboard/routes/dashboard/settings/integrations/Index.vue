<script setup>
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { computed, onMounted, ref } from 'vue';
import { useBranding } from 'shared/composables/useBranding';
import { picoSearch } from '@chatwoot/pico-search';
import IntegrationItem from './IntegrationItem.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import {
  CRM_AI_INTEGRATION_ID,
  isCrmAiKeyPending,
} from 'dashboard/helper/crmAiKey';

const store = useStore();
const getters = useStoreGetters();
const { replaceInstallationName } = useBranding();

const searchQuery = ref('');
const uiFlags = getters['integrations/getUIFlags'];

const integrationList = computed(
  () => getters['integrations/getAppIntegrations'].value
);

// Enquanto falta a chave da OpenAI, o cartão dela vem primeiro e marcado: é o
// passo que destrava o CRM com IA, os agentes e o Guia. Com a chave ligada, a
// lista volta à ordem de sempre.
const chavePendente = computed(() => {
  const crmAi = integrationList.value.find(
    item => item.id === CRM_AI_INTEGRATION_ID
  );
  return Boolean(crmAi) && isCrmAiKeyPending(crmAi);
});

const orderedIntegrationList = computed(() => {
  if (!chavePendente.value) return integrationList.value;
  return [
    ...integrationList.value.filter(item => item.id === CRM_AI_INTEGRATION_ID),
    ...integrationList.value.filter(item => item.id !== CRM_AI_INTEGRATION_ID),
  ];
});

const filteredIntegrationList = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return orderedIntegrationList.value;
  return picoSearch(orderedIntegrationList.value, query, [
    'name',
    'description',
  ]);
});

const isDestaque = item =>
  chavePendente.value && item.id === CRM_AI_INTEGRATION_ID;

onMounted(() => {
  store.dispatch('integrations/get');
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('INTEGRATION_SETTINGS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('INTEGRATION_SETTINGS.HEADER')"
        :description="
          replaceInstallationName($t('INTEGRATION_SETTINGS.DESCRIPTION'))
        "
        :link-text="$t('INTEGRATION_SETTINGS.LEARN_MORE')"
        :search-placeholder="$t('INTEGRATION_SETTINGS.SEARCH_PLACEHOLDER')"
        feature-name="integrations"
      />
    </template>
    <template #body>
      <div class="flex-grow flex-shrink overflow-auto">
        <span
          v-if="!filteredIntegrationList.length && searchQuery"
          class="flex-1 flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
        >
          {{ $t('INTEGRATION_SETTINGS.NO_RESULTS') }}
        </span>
        <div
          v-else
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
        >
          <IntegrationItem
            v-for="item in filteredIntegrationList"
            :id="item.id"
            :key="item.id"
            :logo="item.logo"
            :name="item.name"
            :description="item.description"
            :enabled="item.enabled"
            :highlighted="isDestaque(item)"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
