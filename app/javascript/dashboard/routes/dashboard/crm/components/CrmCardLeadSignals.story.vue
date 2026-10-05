<script setup>
import CrmCardLeadForm from './CrmCardLeadForm.vue';
import CrmCardMetaConversion from './CrmCardMetaConversion.vue';

const leadForm = {
  link_code: 'AB3CDE',
  captured_at: new Date(Date.now() - 12 * 60 * 1000).toISOString(),
  fields: [
    { key: 'destination', label: 'Destino', value: 'América do Norte - EUA' },
    { key: 'departure', label: 'Ida', value: '12/10/2026' },
    { key: 'return', label: 'Volta', value: '28/10/2026' },
    { key: 'ages', label: 'Idades', value: '72, 68' },
  ],
};
const conversions = [
  { title: 'Sent', row: { status: 'accepted', event_type: 'won' } },
  {
    title: 'Not sent · missing Pixel',
    row: { status: 'skipped', error_message: 'missing_pixel' },
  },
  {
    title: 'Not sent · older than 7 days',
    row: { status: 'skipped', error_message: 'event_too_old' },
  },
  {
    title: 'Not sent · site sent no ad data',
    row: { status: 'skipped', error_message: 'missing_ctwa_clid' },
    fromWebsite: true,
  },
  {
    title: 'Failed · Meta message',
    row: {
      status: 'error',
      event_type: 'won',
      error_message: '(#100) Missing Permission',
    },
  },
];
</script>

<!-- eslint-disable vue/no-undef-components -->
<template>
  <Story
    title="CRM/Card/Landing page signals"
    :layout="{ type: 'grid', width: '420px' }"
  >
    <Variant title="Form details">
      <div class="rounded-xl border border-n-weak bg-n-surface-1 p-4">
        <CrmCardLeadForm :lead-form="leadForm" />
      </div>
    </Variant>
    <Variant
      v-for="conversion in conversions"
      :key="conversion.title"
      :title="`Meta conversion · ${conversion.title}`"
    >
      <div class="bg-n-background p-4">
        <CrmCardMetaConversion
          :conversion="conversion.row"
          :from-website="conversion.fromWebsite"
        />
      </div>
    </Variant>
  </Story>
</template>
