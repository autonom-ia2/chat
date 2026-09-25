<script setup>
// Frente de telefone: botões de WhatsApp (com a verificação em andamento) e
// ligar, no rodapé do card do lead.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import {
  isWhatsAppUnavailable,
  isWhatsAppVerified,
  leadPhoneUrl,
  leadWhatsAppUrl,
} from '../../utils/leadPhone';
import { phoneRegionFromSettings } from '../../utils/phoneContract';

defineProps({
  lead: { type: Object, required: true },
});

const { t } = useI18n();
const { isWhatsAppChecking, settings } = useProspectingSearchContext();
const phoneRegion = computed(() => phoneRegionFromSettings(settings.value));
</script>

<template>
  <span
    v-if="lead.phone && isWhatsAppChecking(lead)"
    class="inline-flex h-8 items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-2 px-3 text-xs font-medium text-n-slate-10"
  >
    <span
      class="size-3 animate-spin rounded-full border-2 border-n-slate-5 border-t-n-slate-11"
    />
    {{ t('PROSPECTING.SEARCH.CHECKING_WHATSAPP') }}
  </span>
  <a
    v-else-if="
      lead.phone &&
      !isWhatsAppUnavailable(lead) &&
      leadWhatsAppUrl(lead, phoneRegion)
    "
    :href="leadWhatsAppUrl(lead, phoneRegion)"
    target="_blank"
    rel="noopener noreferrer"
    class="inline-flex h-8 items-center gap-1 rounded-md px-3 text-xs font-semibold transition-colors"
    :class="
      isWhatsAppVerified(lead)
        ? 'bg-n-teal-9 text-white shadow-sm hover:bg-n-teal-10'
        : 'border border-n-teal-5 bg-n-solid-1 text-n-teal-11 hover:bg-n-teal-2'
    "
  >
    <span class="i-lucide-message-circle size-3.5" />
    {{ t('PROSPECTING.SEARCH.WHATSAPP') }}
  </a>
  <span
    v-else
    class="inline-flex h-8 cursor-not-allowed items-center gap-1 rounded-md border border-n-weak bg-n-solid-2 px-3 text-xs font-medium text-n-slate-8"
  >
    <span class="i-lucide-message-circle size-3.5" />
    {{ t('PROSPECTING.SEARCH.NO_WHATSAPP') }}
  </span>
  <a
    v-if="leadPhoneUrl(lead, phoneRegion)"
    :href="leadPhoneUrl(lead, phoneRegion)"
    class="inline-flex h-8 items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-1 px-3 text-xs font-semibold text-n-slate-12 transition-colors hover:bg-n-solid-2"
  >
    <span class="i-lucide-phone size-3.5" />
    {{ t('PROSPECTING.SEARCH.CALL') }}
  </a>
</template>
