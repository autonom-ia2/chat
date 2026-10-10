<script setup>
import { computed, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import ActionButton from './ActionButton.vue';
import BrandHeader from './BrandHeader.vue';
import FormFooter from './FormFooter.vue';
import PhoneField from './PhoneField.vue';
import TextField from './TextField.vue';
import WhatsAppButton from './WhatsAppButton.vue';

// "Nenhum horário serve?" (J2-A10): nome e WhatsApp viram pedido de contato no card, em vez de lead perdido. Pelo
// link do cliente não pede de novo o que o convite já sabe (o servidor usa o contato do convite). Pedido enviado: o
// foco vai para o título novo, e o leitor de tela anuncia que deu certo.
const {
  page,
  form,
  fieldErrors,
  invite,
  askName,
  askPhone,
  isContactRequested,
  goBack,
  submitContactRequest,
} = useFlow();
const { t } = useI18n();

const agentName = computed(() => page.value.agent_name || '');
const body = computed(() => {
  const suffix = invite.isInvite.value && !askPhone.value ? '_INVITE' : '';
  return agentName.value
    ? t(`BOOKING_V2.NO_SLOT.BODY${suffix}`, { name: agentName.value })
    : t(`BOOKING_V2.NO_SLOT.BODY_NO_NAME${suffix}`);
});

watch(isContactRequested, isDone => {
  if (!isDone) return;
  nextTick(() => document.querySelector('[data-step-heading]')?.focus());
});
</script>

<template>
  <section class="flex flex-col gap-6" aria-labelledby="step-heading">
    <BrandHeader :page="page" />
    <template v-if="isContactRequested">
      <h1
        id="step-heading"
        data-step-heading
        tabindex="-1"
        class="text-2xl font-bold text-slate-900 focus:outline-none"
      >
        {{ t('BOOKING_V2.NO_SLOT.DONE_TITLE') }}
      </h1>
      <p class="text-base text-slate-800">
        {{ t('BOOKING_V2.NO_SLOT.DONE_BODY') }}
      </p>
      <WhatsAppButton :url="page.contact_whatsapp_url" />
    </template>
    <template v-else>
      <h1
        id="step-heading"
        data-step-heading
        tabindex="-1"
        class="text-2xl font-bold text-slate-900 focus:outline-none"
      >
        {{ t('BOOKING_V2.NO_SLOT.TITLE') }}
      </h1>
      <p class="text-base text-slate-800">{{ body }}</p>
      <form
        class="flex flex-col gap-5"
        novalidate
        @submit.prevent="submitContactRequest"
      >
        <TextField
          v-if="askName"
          id="contact-name"
          v-model="form.name"
          :label="t('BOOKING_V2.DETAILS.NAME')"
          :error="fieldErrors.name"
          autocomplete="name"
          required
        />
        <PhoneField
          v-if="askPhone"
          id="contact-phone"
          v-model:country="form.countryCode"
          v-model:national="form.phone"
          :label="t('BOOKING_V2.DETAILS.PHONE')"
          :error="fieldErrors.phone"
        />
        <FormFooter :submit-label="t('BOOKING_V2.NO_SLOT.SUBMIT')" />
      </form>
      <ActionButton variant="ghost" @click="goBack">
        {{ t('BOOKING_V2.BACK') }}
      </ActionButton>
    </template>
  </section>
</template>
