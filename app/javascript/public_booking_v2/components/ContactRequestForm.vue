<script setup>
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import FormFooter from './FormFooter.vue';
import PhoneField from './PhoneField.vue';
import TextField from './TextField.vue';

// Pedido de contato: nome e WhatsApp viram card e ligação para o responsável. Usado no "Nenhum horário serve?"
// (J2-A10) e na página pausada (RA-17, #1401). Pelo link do cliente não pede de novo o que o convite já sabe.
const { form, fieldErrors, askName, askPhone, submitContactRequest } =
  useFlow();
const { t } = useI18n();
</script>

<template>
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
</template>
