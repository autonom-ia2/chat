<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useFunctionGetter, useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { frontendURL } from 'dashboard/helper/URLHelper';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { isAdmin } = useAdmin();

const integrationLoaded = ref(false);

const integration = useFunctionGetter('integrations/getIntegration', 'crm_n8n');
const uiFlags = useMapGetter('integrations/getUIFlags');
const accountId = computed(() => store.getters.getCurrentAccountId);

// CRM trigger events (plan D3; resolved/cancelled from #1144). Canonical dotted strings match
// Webhook::CRM_WEBHOOK_EVENTS / Events::Types::CRM_CARD_* exactly.
const TRIGGER_EVENTS = [
  'crm.card.created',
  'crm.card.moved',
  'crm.card.won',
  'crm.card.lost',
  'crm.card.resolved',
  'crm.card.cancelled',
  'crm.card.reopened',
  'crm.card.archived',
];

// Deep-link to the CRM integration tokens settings page (mint a scoped token).
const tokensLink = computed(() =>
  frontendURL(`accounts/${accountId.value}/crm/settings/integration-tokens`)
);

// Deep-link to the account Webhook creator (the CRM events section is shown
// there when CRM Kanban is enabled — see W4.2). Admin-only route.
const webhookLink = computed(() =>
  frontendURL(`accounts/${accountId.value}/settings/integrations/webhook`)
);

const initialize = async () => {
  await store.dispatch('integrations/get', 'crm_n8n');
  integrationLoaded.value = true;
};

onMounted(() => {
  initialize();
});
</script>

<template>
  <SettingsLayout :is-loading="!integrationLoaded || uiFlags.isFetching">
    <template #header>
      <BaseSettingsHeader
        :title="$t('INTEGRATION_SETTINGS.CRM_N8N.HEADER')"
        description=""
        feature-name="crm_integration"
        :back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"
      />
    </template>
    <template #body>
      <div class="flex flex-col gap-6">
        <div
          class="flex items-start justify-start p-6 outline outline-n-container outline-1 bg-n-card rounded-xl gap-6 flex-col lg:flex-row lg:items-center"
        >
          <div class="flex h-16 w-16 items-center justify-center flex-shrink-0">
            <img
              :src="`/dashboard/images/integrations/${integration.id}.png`"
              class="max-w-full rounded-md border border-n-weak shadow-sm block dark:hidden bg-n-alpha-3 dark:bg-n-alpha-2"
            />
            <img
              :src="`/dashboard/images/integrations/${integration.id}-dark.png`"
              class="max-w-full rounded-md border border-n-weak shadow-sm hidden dark:block bg-n-alpha-3 dark:bg-n-alpha-2"
            />
          </div>
          <div class="flex flex-col gap-1">
            <h3 class="text-heading-1 text-n-slate-12">
              {{ integration.name }}
            </h3>
            <p class="text-n-slate-11 text-body-main">
              {{ integration.description }}
            </p>
            <p class="text-n-slate-11 text-body-small">
              {{ $t('INTEGRATION_SETTINGS.CRM_N8N.POWERED_BY') }}
            </p>
          </div>
        </div>

        <div
          class="flex flex-col p-6 outline outline-1 outline-n-container bg-n-card rounded-xl gap-4"
        >
          <h3 class="text-heading-2 text-n-slate-12">
            {{ $t('INTEGRATION_SETTINGS.CRM_N8N.SETUP.TITLE') }}
          </h3>
          <p class="text-n-slate-11 text-body-main">
            {{ $t('INTEGRATION_SETTINGS.CRM_N8N.SETUP.DESCRIPTION') }}
          </p>

          <div v-if="isAdmin" class="flex flex-wrap gap-3">
            <router-link :to="tokensLink">
              <Button
                blue
                faded
                sm
                :label="$t('INTEGRATION_SETTINGS.CRM_N8N.SETUP.TOKENS_CTA')"
              />
            </router-link>
            <router-link :to="webhookLink">
              <Button
                slate
                faded
                sm
                :label="$t('INTEGRATION_SETTINGS.CRM_N8N.SETUP.WEBHOOK_CTA')"
              />
            </router-link>
          </div>
          <p v-else class="text-n-slate-11 text-body-small">
            {{ $t('INTEGRATION_SETTINGS.CRM_N8N.SETUP.ADMIN_ONLY') }}
          </p>
        </div>

        <div
          class="flex flex-col p-6 outline outline-1 outline-n-container bg-n-card rounded-xl gap-4"
        >
          <h3 class="text-heading-2 text-n-slate-12">
            {{ $t('INTEGRATION_SETTINGS.CRM_N8N.EVENTS.TITLE') }}
          </h3>
          <p class="text-n-slate-11 text-body-main">
            {{ $t('INTEGRATION_SETTINGS.CRM_N8N.EVENTS.DESCRIPTION') }}
          </p>
          <ul class="flex flex-col gap-2">
            <li
              v-for="event in TRIGGER_EVENTS"
              :key="event"
              class="flex items-center gap-3"
            >
              <code
                class="px-2 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-12 font-mono"
              >
                {{ event }}
              </code>
              <span class="text-n-slate-11 text-body-small">
                {{
                  $t(
                    `INTEGRATION_SETTINGS.CRM_N8N.EVENTS.LIST.${event
                      .toUpperCase()
                      .replace(/\./g, '_')}`
                  )
                }}
              </span>
            </li>
          </ul>
        </div>

        <div
          class="flex flex-col p-6 outline outline-1 outline-n-amber-9/40 bg-n-amber-9/10 rounded-xl gap-2"
        >
          <h3 class="text-heading-2 text-n-slate-12">
            {{ $t('INTEGRATION_SETTINGS.CRM_N8N.REQUIREMENTS.TITLE') }}
          </h3>
          <p class="text-n-slate-11 text-body-main">
            {{ $t('INTEGRATION_SETTINGS.CRM_N8N.REQUIREMENTS.PUBLIC_URL') }}
          </p>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
