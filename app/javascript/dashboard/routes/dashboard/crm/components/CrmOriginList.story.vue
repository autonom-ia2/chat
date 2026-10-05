<script setup>
import { nextTick, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmOriginList from './CrmOriginList.vue';
import CrmKanbanCard from './CrmKanbanCard.vue';

// Review story (#1034): every touch of a contact, first to last, with the
// Meta names resolved — and the same touches before the names arrive (IDs).
useI18n().locale.value = 'pt_BR';

const ctwaTouch = {
  source: 'meta_ctwa',
  source_id: '120254710067060999',
  source_type: 'ad',
  headline: 'Cotação Rápida',
  source_url: 'https://www.instagram.com/p/C9xYz12AbCd/',
  campaign_name: 'Seguro Viagem · Julho',
  adset_name: 'Brasil 25-45 · Interesses viagem',
  touched_at: '2026-07-10T14:32:00Z',
};
const siteTouch = {
  source: 'meta_paid',
  source_id: 'site:AB3CDE:120254710067060416',
  headline: 'LP Seguro Viagem · Viagem EUA Outubro',
  source_url: 'https://placement.com.br/seguro-viagem',
  utm_campaign: '120254710067060416',
  utm_term: '120254710067060417',
  utm_content: '120254710067060418',
  campaign_name: 'Viagem EUA Outubro',
  adset_name: 'Conjunto 60+',
  ad_name: 'Vídeo 2 · depoimento',
  touched_at: '2026-07-14T19:05:00Z',
};
const withNames = [ctwaTouch, siteTouch];

// Before the token is connected: Meta's automatic parameters, only numbers.
const withIds = [
  {
    source: 'meta_ctwa',
    source_id: '120254710067060999',
    source_type: 'ad',
    headline: 'Cotação Rápida',
    source_url: 'https://www.instagram.com/p/C9xYz12AbCd/',
    touched_at: '2026-07-10T14:32:00Z',
  },
  {
    source: 'meta_paid',
    source_id: 'site:AB3CDE:120254710067060416',
    headline: 'LP Seguro Viagem · 120254710067060416',
    source_url: 'https://placement.com.br/seguro-viagem',
    utm_campaign: '120254710067060416',
    utm_term: '120254710067060417',
    utm_content: '120254710067060418',
    touched_at: '2026-07-14T19:05:00Z',
  },
  {
    source: 'meta_paid',
    source_id: 'site:AB3CDE:120254710067060500',
    headline: 'LP Seguro Viagem · 120254710067060500',
    source_url: 'https://placement.com.br/seguro-viagem',
    utm_campaign: '120254710067060500',
    touched_at: '2026-08-02T11:20:00Z',
  },
];

const card = {
  id: 7,
  title: 'Seguro viagem EUA',
  contact: { id: 3, name: 'Marina Albuquerque' },
  value_cents: 37780,
  currency: 'BRL',
  responsible: { type: 'agent', name: 'Rodrigo' },
  last_message_at: Math.floor(Date.now() / 1000) - 20 * 60,
  campaigns: [...withNames, withIds[2]],
};

// Opens the "+N" once the card is on screen, as a click would.
const OpenMore = {
  setup(_, { slots }) {
    onMounted(async () => {
      await nextTick();
      setTimeout(
        () => document.querySelector('[data-crm-origin-more]')?.click(),
        300
      );
    });
    return () => slots.default?.();
  },
};
</script>

<!-- eslint-disable vue/no-undef-components -->
<template>
  <Story
    title="CRM/Card/Contact origins"
    :layout="{ type: 'grid', width: '420px' }"
  >
    <Variant title="Two touches · names">
      <div class="bg-n-background p-4">
        <div class="rounded-xl border border-n-weak bg-n-surface-1 p-4">
          <CrmOriginList :campaigns="withNames" />
        </div>
      </div>
    </Variant>
    <Variant title="Touches · IDs only">
      <div class="bg-n-background p-4">
        <div class="rounded-xl border border-n-weak bg-n-surface-1 p-4">
          <CrmOriginList :campaigns="withIds" />
        </div>
      </div>
    </Variant>
    <Variant title="Kanban · +N open">
      <OpenMore>
        <div class="min-h-[40rem] bg-n-background p-4">
          <div class="w-72">
            <CrmKanbanCard :card="card" stage-color="#22c55e" />
          </div>
        </div>
      </OpenMore>
    </Variant>
  </Story>
</template>
