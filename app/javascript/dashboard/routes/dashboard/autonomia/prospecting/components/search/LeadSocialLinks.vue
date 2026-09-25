<script setup>
// Botões de Instagram, Facebook e LinkedIn no rodapé do card, como no Orth
// (ResultsTable.tsx): quadrados, só ícone, cor da marca, e só quando o lead
// tem o link. Link sem esquema ganha https://, como lá.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  lead: { type: Object, required: true },
});

const { t } = useI18n();

const NETWORKS = [
  {
    key: 'INSTAGRAM',
    label: t('PROSPECTING.SEARCH.CARD_SOCIAL.INSTAGRAM'),
    field: 'enriched_instagram',
    icon: 'i-ri-instagram-line',
    tone: 'text-[#E1306C] hover:border-n-ruby-5 hover:bg-n-ruby-2',
  },
  {
    key: 'FACEBOOK',
    label: t('PROSPECTING.SEARCH.CARD_SOCIAL.FACEBOOK'),
    field: 'enriched_facebook',
    icon: 'i-ri-facebook-circle-fill',
    tone: 'text-[#1877F2] hover:border-n-blue-5 hover:bg-n-blue-2',
  },
  {
    key: 'LINKEDIN',
    label: t('PROSPECTING.SEARCH.CARD_SOCIAL.LINKEDIN'),
    field: 'enriched_linkedin',
    icon: 'i-ri-linkedin-box-fill',
    tone: 'text-[#0A66C2] hover:border-n-blue-5 hover:bg-n-blue-2',
  },
];

const socialUrl = value =>
  value.startsWith('http') ? value : `https://${value}`;

const links = computed(() =>
  NETWORKS.map(network => ({
    ...network,
    value: String(props.lead[network.field] || '').trim(),
  }))
    .filter(network => network.value)
    .map(network => ({ ...network, href: socialUrl(network.value) }))
);
</script>

<template>
  <a
    v-for="link in links"
    :key="link.key"
    :href="link.href"
    target="_blank"
    rel="noopener noreferrer"
    :title="link.label"
    :aria-label="link.label"
    class="inline-flex size-8 items-center justify-center rounded-md border border-n-weak bg-n-solid-1 transition-colors"
    :class="link.tone"
  >
    <span :class="link.icon" class="size-4" />
  </a>
</template>
