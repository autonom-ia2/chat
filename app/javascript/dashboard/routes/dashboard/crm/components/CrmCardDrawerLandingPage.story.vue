<script setup>
import { useI18n } from 'vue-i18n';
import { createMemoryHistory, createRouter } from 'vue-router';
import MetaConversionsAPI from 'dashboard/api/metaConversions';
import CrmCardDrawer from './CrmCardDrawer.vue';

// Review story (#1011): the real card drawer for a lead that came from a
// landing page — origin with campaign, ad set and ad, the form the customer
// filled in, and the Meta conversion badge. Each variant answers the badge
// request with a different row.
useI18n().locale.value = 'pt_BR';

const stages = [
  { id: 10, name: 'Novo lead', position: 1, stage_type: 'open' },
  { id: 11, name: 'Cotação enviada', position: 2, stage_type: 'open' },
  { id: 12, name: 'Ganho', position: 3, stage_type: 'won' },
];
const card = {
  id: 7,
  title: 'Seguro viagem EUA · Maria Souza',
  stage_id: 12,
  status: 'won',
  value_cents: 37780,
  currency: 'BRL',
  inbox: { id: 38, name: 'WhatsApp Vendas' },
  contact: { id: 3, name: 'Maria Souza', phone_number: '+5511988887777' },
  conversation: { id: 265, display_id: 265 },
  campaigns: [
    {
      source: 'meta_paid',
      source_id: 'site:AB3CDE:120211',
      headline: 'LP Seguro Viagem · Viagem EUA Outubro',
      source_url: 'https://placement.com.br/seguro-viagem',
      utm_campaign: 'Viagem EUA Outubro',
      utm_term: 'Conjunto 60+',
      utm_content: 'Video 2',
    },
  ],
  lead_form: {
    link_code: 'AB3CDE',
    captured_at: new Date(Date.now() - 12 * 60 * 1000).toISOString(),
    fields: [
      { key: 'destination', label: 'Destino', value: 'América do Norte - EUA' },
      { key: 'departure', label: 'Ida', value: '12/10/2026' },
      { key: 'return', label: 'Volta', value: '28/10/2026' },
      { key: 'ages', label: 'Idades', value: '72, 68' },
    ],
  },
};
const ROWS = {
  sent: { status: 'accepted', event_type: 'won' },
  missingSignals: {
    status: 'skipped',
    event_type: 'won',
    error_message: 'missing_signals',
  },
  failed: {
    status: 'error',
    event_type: 'won',
    error_message:
      '(#100) Missing Permission: the system user cannot access pixel 2164882667623689',
  },
};
const withConversion =
  key =>
  ({ app }) => {
    MetaConversionsAPI.getForCards = async () => ({
      data: { payload: [{ card_id: card.id, ...ROWS[key] }] },
    });
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: '/:path(.*)*', component: { render: () => null } }],
    });
    router.push('/app/accounts/1/crm');
    app.use(router);
  };
</script>

<!-- eslint-disable vue/no-undef-components -->
<template>
  <Story
    title="CRM/Card/Drawer · landing page lead"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Meta · sent" :setup-app="withConversion('sent')">
      <div class="h-screen bg-n-background">
        <CrmCardDrawer
          show
          mode="edit"
          :card="card"
          :stages="stages"
          :pipeline-id="1"
        />
      </div>
    </Variant>
    <Variant
      title="Meta · not sent (no site signals)"
      :setup-app="withConversion('missingSignals')"
    >
      <div class="h-screen bg-n-background">
        <CrmCardDrawer
          show
          mode="edit"
          :card="card"
          :stages="stages"
          :pipeline-id="1"
        />
      </div>
    </Variant>
    <Variant title="Meta · failed" :setup-app="withConversion('failed')">
      <div class="h-screen bg-n-background">
        <CrmCardDrawer
          show
          mode="edit"
          :card="card"
          :stages="stages"
          :pipeline-id="1"
        />
      </div>
    </Variant>
  </Story>
</template>
