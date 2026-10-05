<script setup>
import TrackedLinkCampaignTable from './TrackedLinkCampaignTable.vue';

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
// Seats without revenue permission get no financial fields from the API.
const withoutRevenue = campaigns.map(
  // eslint-disable-next-line camelcase, no-unused-vars
  ({ won_cards, won_value_by_currency, ...rest }) => rest
);
</script>

<!-- eslint-disable vue/no-undef-components -->
<template>
  <Story
    title="Campaigns/TrackedLinks/CampaignTable"
    :layout="{ type: 'grid', width: '760px' }"
  >
    <Variant title="With campaigns">
      <div class="bg-n-background p-4">
        <TrackedLinkCampaignTable
          :campaigns="campaigns"
          origin-name="LP Seguro Viagem"
        />
      </div>
    </Variant>
    <Variant title="Without revenue permission">
      <div class="bg-n-background p-4">
        <TrackedLinkCampaignTable
          :campaigns="withoutRevenue"
          origin-name="LP Seguro Viagem"
        />
      </div>
    </Variant>
    <Variant title="Empty">
      <div class="bg-n-background p-4">
        <TrackedLinkCampaignTable origin-name="LP Seguro Viagem" />
      </div>
    </Variant>
  </Story>
</template>
