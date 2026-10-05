<script setup>
import TrackedLinkWebsitePanel from './TrackedLinkWebsitePanel.vue';
import TrackedLinkWebsitePreview from './TrackedLinkWebsitePreview.vue';

const AD_PARAMS =
  'utm_source=meta&utm_medium=paid&utm_campaign={{campaign.name}}&utm_term={{adset.name}}&utm_content={{ad.name}}&utm_id={{campaign.id}}';
const campaigns = [
  {
    campaign_key: '120211',
    name: 'Viagem EUA Outubro',
    clicks: 40,
    conversations: 31,
    won_cards: 4,
    won_value_by_currency: { BRL: 151120 },
  },
  {
    campaign_key: 'c:5f1a9e0b2c',
    name: 'Europa 60+',
    clicks: 18,
    conversations: 12,
    won_cards: 1,
    won_value_by_currency: { BRL: 37780 },
  },
  {
    campaign_key: 'none',
    name: null,
    clicks: 5,
    conversations: 3,
    won_cards: 0,
    won_value_by_currency: {},
  },
];
const link = lastSignalAt => ({
  id: 1,
  name: 'LP Seguro Viagem',
  code: 'AB3CDE',
  usage: 'website',
  allowed_origins: ['https://placement.com.br'],
  last_signal_at: lastSignalAt,
  signal_url: 'https://chat.hub2you.ai/l/AB3CDE/clicks',
  ad_url_params: AD_PARAMS,
  campaigns,
});
const recent = new Date(Date.now() - 6 * 60 * 1000).toISOString();
const stale = new Date(Date.now() - 4 * 24 * 3600 * 1000).toISOString();
</script>

<!-- eslint-disable vue/no-undef-components -->
<template>
  <Story
    title="Campaigns/TrackedLinks/Website"
    :layout="{ type: 'grid', width: '360px' }"
  >
    <Variant title="Panel · recent signal">
      <div class="rounded-xl border border-n-weak bg-n-solid-1">
        <TrackedLinkWebsitePanel :link="link(recent)" can-manage />
      </div>
    </Variant>
    <Variant title="Panel · old signal">
      <div class="rounded-xl border border-n-weak bg-n-solid-1">
        <TrackedLinkWebsitePanel :link="link(stale)" can-manage />
      </div>
    </Variant>
    <Variant title="Panel · never received, read only">
      <div class="rounded-xl border border-n-weak bg-n-solid-1">
        <TrackedLinkWebsitePanel :link="link(null)" />
      </div>
    </Variant>
    <Variant title="Create preview">
      <div class="bg-n-slate-2 p-7">
        <TrackedLinkWebsitePreview
          origin="https://placement.com.br"
          inbox-name="WhatsApp Vendas"
        />
      </div>
    </Variant>
  </Story>
</template>
