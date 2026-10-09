<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { whenLabel } from '../helpers/datetime';
import { locationKey } from '../helpers/locations';
import { safeAbsoluteUrl, safeUrl } from '../helpers/url';
import ActionButton from './ActionButton.vue';
import BrandHeader from './BrandHeader.vue';
import WhatsAppButton from './WhatsAppButton.vue';

// Pronto (J2-A11): "Salvar na minha agenda" baixa o .ics; "Falar no WhatsApp" quando a página tem número;
// "Entrar na reunião" só para link http/https. Não promete mensagem que pode não sair (J2-A6).
const { page, result, greetingName } = useFlow();
const { t, locale } = useI18n();

const when = computed(() =>
  result.value?.starts_at ? whenLabel(result.value.starts_at, locale.value) : ''
);
const agentName = computed(
  () => page.value.agent_name || page.value.title || ''
);
const locationText = computed(() =>
  t('BOOKING_V2.DONE.WITH', {
    location: t(
      `BOOKING_V2.LOCATION.${locationKey(result.value?.location?.type)}`
    ),
    name: agentName.value,
  })
);
const address = computed(() => result.value?.location?.address || '');
const icsUrl = computed(() => safeUrl(result.value?.ics_url));
const joinUrl = computed(() =>
  safeAbsoluteUrl(result.value?.location?.join_url)
);
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
        {{ t('BOOKING_V2.DONE.ADDRESS', { address }) }}
      </p>
    </div>
    <div class="flex flex-col gap-3">
      <ActionButton v-if="icsUrl" :href="icsUrl" download>
        {{ t('BOOKING_V2.DONE.SAVE') }}
      </ActionButton>
      <ActionButton v-if="joinUrl" :href="joinUrl" variant="secondary" external>
        {{ t('BOOKING_V2.DONE.JOIN') }}
      </ActionButton>
      <WhatsAppButton
        :url="whatsappUrl"
        variant="secondary"
        :label="t('BOOKING_V2.DONE.WHATSAPP')"
      />
    </div>
    <p v-if="agentName" class="text-center text-base text-slate-600">
      {{ t('BOOKING_V2.DONE.NOTIFIED', { name: agentName }) }}
    </p>
  </section>
</template>
