<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { zoneLabel } from '../helpers/datetime';

// Linha "Horários mostrados em: <fuso de quem abre>". Quem usa só mostra quando o relógio de quem abre é diferente do
// da página (`isOtherClock`): as horas da página estão sempre no relógio de quem abre (RA-08).
const { clientZone } = useFlow();
const { t, locale } = useI18n();

const zone = computed(() => zoneLabel(clientZone, locale.value));
</script>

<template>
  <p data-testid="zone-note" class="text-base text-slate-600">
    {{ t('BOOKING_V2.ZONE', { zone }) }}
  </p>
</template>
