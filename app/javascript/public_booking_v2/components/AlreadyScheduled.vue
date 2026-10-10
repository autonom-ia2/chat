<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { whenLabel } from '../helpers/datetime';
import BrandHeader from './BrandHeader.vue';
import MessageScreen from './MessageScreen.vue';
import WhatsAppButton from './WhatsAppButton.vue';
import ZoneNote from './ZoneNote.vue';

// Link do cliente já usado: mostra o dia e a hora marcados e o WhatsApp. Remarcar e cancelar pelo link chegam na F2-A.
const { page, invite, clientZone, isOtherClock } = useFlow();
const { t, locale } = useI18n();

const agentName = computed(() => page.value.agent_name || '');
const body = computed(() =>
  agentName.value
    ? t('BOOKING_V2.ALREADY.BODY', { name: agentName.value })
    : t('BOOKING_V2.ALREADY.BODY_NO_NAME')
);
const when = computed(() =>
  invite.startsAt.value
    ? whenLabel(invite.startsAt.value, locale.value, clientZone)
    : ''
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <BrandHeader :page="page" />
    <MessageScreen
      icon="i-lucide-calendar-check"
      :title="t('BOOKING_V2.ALREADY.TITLE')"
      :body="body"
    >
      <div
        v-if="when"
        data-testid="already-when"
        class="flex flex-col gap-1 rounded-2xl border-2 border-slate-200 bg-slate-50 p-4"
      >
        <p class="text-lg font-semibold text-slate-900 first-letter:uppercase">
          {{ when }}
        </p>
        <ZoneNote v-if="isOtherClock" />
      </div>
      <p v-if="page.contact_whatsapp_url" class="text-base text-slate-700">
        {{ t('BOOKING_V2.ALREADY.CHANGE') }}
      </p>
      <WhatsAppButton
        :url="page.contact_whatsapp_url"
        variant="primary"
        :label="t('BOOKING_V2.ALREADY.WHATSAPP')"
      />
    </MessageScreen>
  </div>
</template>
