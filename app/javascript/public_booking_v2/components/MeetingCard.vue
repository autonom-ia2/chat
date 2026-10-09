<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { isValidTimeZone, sameClock, whenLabel } from '../helpers/datetime';
import { locationAddress, locationName } from '../helpers/locations';
import { safeAbsoluteUrl } from '../helpers/url';
import ActionButton from './ActionButton.vue';
import ZoneNote from './ZoneNote.vue';

// Cartão da reunião marcada (J5 "Sua conversa"): dia e hora no relógio de quem abre (com a linha do fuso quando é
// outro que o da reunião, RA-08), local com o rótulo do servidor, endereço do presencial, "Entrar" só para link
// http/https e quem atende. `showJoin` falso na reunião cancelada.
const props = defineProps({
  meeting: { type: Object, required: true },
  showJoin: { type: Boolean, default: true },
});

const { page, clientZone } = useFlow();
const { t, locale } = useI18n();

const when = computed(() =>
  props.meeting.starts_at
    ? whenLabel(props.meeting.starts_at, locale.value, clientZone)
    : ''
);
const agentName = computed(
  () => props.meeting.agent_name || page.value?.agent_name || ''
);
const place = computed(() => locationName(props.meeting.location, t));
const placeText = computed(() =>
  agentName.value
    ? t('BOOKING_V2.DONE.WITH', {
        location: place.value,
        name: agentName.value,
      })
    : place.value
);
const address = computed(() => locationAddress(props.meeting.location));
const joinUrl = computed(() =>
  props.showJoin ? safeAbsoluteUrl(props.meeting.location?.join_url) : null
);
const isOtherClock = computed(
  () =>
    isValidTimeZone(props.meeting.timezone) &&
    !sameClock(clientZone, props.meeting.timezone)
);
</script>

<template>
  <div
    data-testid="meeting-card"
    class="flex flex-col gap-1 rounded-2xl border-2 border-slate-200 bg-slate-50 p-4"
  >
    <p class="text-lg font-semibold text-slate-900 first-letter:uppercase">
      {{ when }}
    </p>
    <p class="text-base text-slate-800">{{ placeText }}</p>
    <p v-if="address" class="text-base text-slate-800">
      {{ t('BOOKING_V2.ADDRESS', { address }) }}
    </p>
    <ZoneNote v-if="isOtherClock" />
    <div v-if="joinUrl" class="mt-3">
      <ActionButton :href="joinUrl" variant="secondary" external>
        {{ t('BOOKING_V2.MANAGE.JOIN') }}
      </ActionButton>
    </div>
  </div>
</template>
