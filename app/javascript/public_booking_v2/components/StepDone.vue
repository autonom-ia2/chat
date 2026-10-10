<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { googleCalendarUrl } from '../helpers/calendar';
import { whenLabel } from '../helpers/datetime';
import { locationAddress, locationName } from '../helpers/locations';
import { safeAbsoluteUrl, safeUrl } from '../helpers/url';
import ActionButton from './ActionButton.vue';
import BrandHeader from './BrandHeader.vue';
import ManageLink from './ManageLink.vue';
import WhatsAppButton from './WhatsAppButton.vue';
import ZoneNote from './ZoneNote.vue';

// Pronto (J2-A11): "Salvar na minha agenda" baixa o .ics e, ao lado, "Pôr na Agenda do Google" (no navegador de
// dentro do WhatsApp/Instagram o download pode falhar, RA-15); "Entrar pelo link" só para link http/https; "Falar no
// WhatsApp" quando a página tem número; e o link para guardar (mudar ou cancelar). Não promete mensagem que pode não
// sair (J2-A6).
const { page, result, locations, greetingName, clientZone, isOtherClock } =
  useFlow();
const { t, locale } = useI18n();

const when = computed(() =>
  result.value?.starts_at
    ? whenLabel(result.value.starts_at, locale.value, clientZone)
    : ''
);
const agentName = computed(
  () => page.value.agent_name || page.value.title || ''
);
// O local confirmado, com o nome e o endereço que a página mostrou.
const place = computed(() => {
  const confirmed = result.value?.location || {};
  const shown = locations.value.find(item => item.type === confirmed.type);
  return { ...shown, ...confirmed };
});
const locationText = computed(() =>
  t('BOOKING_V2.DONE.WITH', {
    location: locationName(place.value, t),
    name: agentName.value,
  })
);
const address = computed(() => locationAddress(place.value));
const icsUrl = computed(() => safeUrl(result.value?.ics_url));
const joinUrl = computed(() => safeAbsoluteUrl(place.value.join_url));
const googleUrl = computed(() =>
  googleCalendarUrl({
    title: t('BOOKING_V2.DONE.CALENDAR_TITLE', { name: agentName.value }),
    startsAt: result.value?.starts_at,
    endsAt: result.value?.ends_at,
    location: address.value || joinUrl.value || '',
  })
);
const manageUrl = computed(() => safeAbsoluteUrl(result.value?.manage_url));
const whatsappUrl = computed(
  () => result.value?.contact_whatsapp_url || page.value.contact_whatsapp_url
);
</script>

<template>
  <section class="flex flex-col gap-6" aria-labelledby="step-heading">
    <BrandHeader :page="page" />
    <div class="flex flex-col items-center gap-3 text-center">
      <span
        aria-hidden="true"
        class="flex size-16 items-center justify-center rounded-full bg-[var(--brand)] text-3xl font-bold text-white"
      >
        <span class="i-lucide-check" />
      </span>
      <h1
        id="step-heading"
        data-step-heading
        tabindex="-1"
        class="text-2xl font-bold text-slate-900 focus:outline-none"
      >
        {{
          greetingName
            ? t('BOOKING_V2.DONE.TITLE', { name: greetingName })
            : t('BOOKING_V2.DONE.TITLE_NO_NAME')
        }}
      </h1>
    </div>
    <div
      class="flex flex-col gap-1 rounded-2xl border-2 border-slate-200 bg-slate-50 p-4"
    >
      <p class="text-lg font-semibold text-slate-900 first-letter:uppercase">
        {{ when }}
      </p>
      <p class="text-base text-slate-800">{{ locationText }}</p>
      <p v-if="address" class="text-base text-slate-800">
        {{ t('BOOKING_V2.ADDRESS', { address }) }}
      </p>
      <ZoneNote v-if="isOtherClock" />
    </div>
    <div class="flex flex-col gap-3">
      <ActionButton v-if="joinUrl" :href="joinUrl" external>
        {{ t('BOOKING_V2.DONE.JOIN') }}
      </ActionButton>
      <ActionButton
        v-if="icsUrl"
        :href="icsUrl"
        :variant="joinUrl ? 'secondary' : 'primary'"
        download
      >
        {{ t('BOOKING_V2.DONE.SAVE') }}
      </ActionButton>
      <ActionButton
        v-if="googleUrl"
        :href="googleUrl"
        variant="secondary"
        external
      >
        {{ t('BOOKING_V2.DONE.GOOGLE') }}
      </ActionButton>
      <WhatsAppButton
        :url="whatsappUrl"
        variant="secondary"
        :label="t('BOOKING_V2.DONE.WHATSAPP')"
      />
    </div>
    <ManageLink v-if="manageUrl" :url="manageUrl" />
    <p v-if="agentName" class="text-center text-base text-slate-600">
      {{ t('BOOKING_V2.DONE.NOTIFIED', { name: agentName }) }}
    </p>
  </section>
</template>
