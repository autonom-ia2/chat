<script setup>
// Selo "Cliente" (#1258): o contato já comprou, um dado importante para a abordagem. Lead e visitante não têm selo.
// O texto diz "Cliente" (não só a cor) e o selo nunca encolhe: quem corta com "…" é o nome ao lado.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, fromUnixTime } from 'date-fns';

const props = defineProps({
  contact: { type: Object, default: null },
  // Topo da conversa: "Cliente desde mm/aaaa".
  showSince: { type: Boolean, default: false },
});

const { t } = useI18n();

const isCustomer = computed(() => props.contact?.contact_type === 'customer');

const label = computed(() => {
  const since = props.contact?.customer_since;
  if (!props.showSince || !since) return t('CONTACT_PANEL.CUSTOMER');
  return t('CONTACT_PANEL.CUSTOMER_SINCE', {
    date: format(fromUnixTime(since), 'MM/yyyy'),
  });
});
</script>

<template>
  <span
    v-if="isCustomer"
    class="inline-flex shrink-0 items-center gap-1 whitespace-nowrap rounded-md bg-n-teal-3 px-1.5 align-middle text-xs font-medium normal-case leading-5 text-n-teal-11"
    data-customer-badge
  >
    <span class="i-lucide-badge-check size-3.5 shrink-0" aria-hidden="true" />
    {{ label }}
  </span>
</template>
