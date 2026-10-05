<script setup>
import { useI18n } from 'vue-i18n';
import CtwaTrackedLinksAPI from 'dashboard/api/ctwaTrackedLinks';
import InboxesAPI from 'dashboard/api/inboxes';
import TrackedLinksPage from './TrackedLinksPage.vue';

// Review story (#1011): the real Links page with a landing page origin
// selected. The two API calls the page makes are answered with fixtures; each
// variant decides whether the seat sees revenue (administrators only).
useI18n().locale.value = 'pt_BR';

const AD_PARAMS =
  'utm_source=meta&utm_medium=paid&utm_campaign={{campaign.name}}&utm_term={{adset.name}}&utm_content={{ad.name}}&utm_id={{campaign.id}}';
const inboxes = [
  { id: 38, name: 'WhatsApp Vendas', channel_type: 'Channel::Whatsapp' },
];
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
// What a seat without revenue permission receives: no financial fields at all.
const withoutRevenue = campaigns.map(
  // eslint-disable-next-line camelcase, no-unused-vars
  ({ won_cards, won_value_by_currency, ...rest }) => rest
);
const links = (list, site = {}) => [
  {
    id: 2,
    name: 'LP Seguro Viagem',
    code: 'AB3CDE',
    usage: 'website',
    inbox_id: 38,
    clicks_count: 63,
    conversations_count: 46,
    allowed_origins: ['https://placement.com.br'],
    last_signal_at: new Date(Date.now() - 6 * 60 * 1000).toISOString(),
    signal_url: 'https://chat.hub2you.ai/l/AB3CDE/clicks',
    ad_url_params: AD_PARAMS,
    campaigns: list,
    ...site,
  },
  {
    id: 1,
    name: 'Panfleto Expo Viagem',
    code: 'QR7K2M',
    usage: 'direct',
    inbox_id: 38,
    clicks_count: 120,
    conversations_count: 37,
    short_url: 'https://chat.hub2you.ai/l/QR7K2M',
    prefilled_text: 'Olá! Vi o panfleto na feira.',
  },
];
const answerWith = (list, site) => () => {
  InboxesAPI.get = async () => ({ data: { payload: inboxes } });
  CtwaTrackedLinksAPI.get = async () => ({
    data: { payload: links(list, site) },
  });
};
</script>

<!-- eslint-disable vue/no-undef-components -->
<template>
  <Story
    title="Campaigns/TrackedLinks/Page"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant
      title="Website origin · with revenue"
      :setup-app="answerWith(campaigns)"
    >
      <div class="h-screen bg-n-background">
        <TrackedLinksPage />
      </div>
    </Variant>
    <Variant
      title="Website origin · without revenue permission"
      :setup-app="answerWith(withoutRevenue)"
    >
      <div class="h-screen bg-n-background">
        <TrackedLinksPage />
      </div>
    </Variant>
    <Variant
      title="Website origin · waiting for the first click"
      :setup-app="
        answerWith([], {
          last_signal_at: null,
          clicks_count: 0,
          conversations_count: 0,
        })
      "
    >
      <div class="h-screen bg-n-background">
        <TrackedLinksPage />
      </div>
    </Variant>
    <Variant
      title="Website origin · no site allowed"
      :setup-app="
        answerWith([], {
          allowed_origins: [],
          last_signal_at: null,
          clicks_count: 0,
          conversations_count: 0,
        })
      "
    >
      <div class="h-screen bg-n-background">
        <TrackedLinksPage />
      </div>
    </Variant>
  </Story>
</template>
