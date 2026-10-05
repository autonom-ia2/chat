<script setup>
import { nextTick, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import MetaAdsNamesCard from './MetaAdsNamesCard.vue';

// Review story (#1034): the "Meta campaign names" block in its three states,
// and the connect dialog after Meta refused a token without ads_read.
useI18n().locale.value = 'pt_BR';

const answerWith =
  (connection, update = null) =>
  () => {
    CrmMetaAdsConnectionAPI.get = async () => ({ data: connection });
    CrmMetaAdsConnectionAPI.update =
      update || (async () => ({ data: connection }));
  };

const hoursAgo = hours =>
  new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();
const notConnected = { configured: false };
const connected = {
  configured: true,
  status: 'active',
  last_checked_at: hoursAgo(2),
  last_error: null,
};
const attention = {
  configured: true,
  status: 'invalid',
  last_checked_at: hoursAgo(50),
  last_error: 'Error validating access token: Session has expired',
};
const refuseWithoutAdsRead = async () => {
  const error = new Error('Request failed with status code 422');
  error.response = { status: 422, data: { error: 'missing_ads_read' } };
  throw error;
};

// Opens the dialog, pastes a token and presses "Test and save", as a person would.
const TryToken = {
  setup(_, { slots }) {
    onMounted(async () => {
      await nextTick();
      setTimeout(async () => {
        document.querySelector('[data-testid="meta-ads-connect"]')?.click();
        await nextTick();
        const input = document.querySelector('dialog[open] input');
        if (!input) return;
        input.value = 'EAAGm0PX4ZCpsBAexample';
        input.dispatchEvent(new Event('input'));
        await nextTick();
        document.querySelector('dialog[open] button[type="submit"]')?.click();
      }, 400);
    });
    return () => slots.default?.();
  },
};
</script>

<!-- eslint-disable vue/no-undef-components -->
<template>
  <Story
    title="Campaigns/TrackedLinks/Meta names"
    :layout="{ type: 'grid', width: '640px' }"
  >
    <Variant title="Not connected" :setup-app="answerWith(notConnected)">
      <div class="bg-n-background p-4">
        <MetaAdsNamesCard />
      </div>
    </Variant>
    <Variant title="Connected" :setup-app="answerWith(connected)">
      <div class="bg-n-background p-4">
        <MetaAdsNamesCard />
      </div>
    </Variant>
    <Variant title="Needs attention" :setup-app="answerWith(attention)">
      <div class="bg-n-background p-4">
        <MetaAdsNamesCard />
      </div>
    </Variant>
    <Variant
      title="Dialog · missing ads_read"
      :setup-app="answerWith(notConnected, refuseWithoutAdsRead)"
    >
      <TryToken>
        <div class="min-h-[44rem] bg-n-background p-4">
          <MetaAdsNamesCard />
        </div>
      </TryToken>
    </Variant>
  </Story>
</template>
