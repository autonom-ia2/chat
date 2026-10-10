<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { whenLabel } from '../helpers/datetime';
import {
  locationAddress,
  locationName,
  locationOptions,
} from '../helpers/locations';
import ActionButton from './ActionButton.vue';
import BrandHeader from './BrandHeader.vue';
import ChoiceCards from './ChoiceCards.vue';
import FormFooter from './FormFooter.vue';
import PhoneField from './PhoneField.vue';
import TextField from './TextField.vue';
import ZoneNote from './ZoneNote.vue';

// Confirmar pelo link do cliente (J1 "Confirma"): nada a digitar. O número mascarado aparece; "Mudar o número"
// revela o campo. Sem número no contato, o campo já vem aberto (J1-A11). Sem e-mail, salvo se o local exigir.
const {
  page,
  form,
  invite,
  fieldErrors,
  locations,
  locationType,
  selectedLocation,
  emailRequired,
  selectedSlot,
  clientZone,
  isOtherClock,
  askName,
  askPhone,
  isChangingPhone,
  startPhoneChange,
  goBack,
  submitBooking,
} = useFlow();
const { t, locale } = useI18n();

const when = computed(() =>
  selectedSlot.value
    ? whenLabel(selectedSlot.value, locale.value, clientZone)
    : ''
);
const phoneMasked = computed(() => invite.phoneMasked.value);
const summary = computed(() => {
  const type = selectedLocation.value?.type;
  const name = page.value.agent_name || page.value.title || '';
  const showPhone = phoneMasked.value && !isChangingPhone.value;
  if (showPhone && type === 'whatsapp_video') {
    return t('BOOKING_V2.CONFIRM.WHATSAPP_VIDEO', {
      name,
      phone: phoneMasked.value,
    });
  }
  if (showPhone && type === 'whatsapp_voice') {
    return t('BOOKING_V2.CONFIRM.WHATSAPP_VOICE', {
      name,
      phone: phoneMasked.value,
    });
  }
  return t('BOOKING_V2.CONFIRM.WITH', {
    location: locationName(selectedLocation.value, t),
    name,
  });
});
const address = computed(() => locationAddress(selectedLocation.value));
const options = computed(() => locationOptions(locations.value, t));
const canChangePhone = computed(
  () => !!phoneMasked.value && !isChangingPhone.value
);
</script>

<template>
  <section class="flex flex-col gap-6" aria-labelledby="step-heading">
    <BrandHeader :page="page" />
    <h1
      id="step-heading"
      data-step-heading
      tabindex="-1"
      class="text-2xl font-bold text-slate-900 focus:outline-none"
    >
      {{ t('BOOKING_V2.CONFIRM.TITLE') }}
    </h1>
    <div
      class="flex flex-col gap-1 rounded-2xl border-2 border-slate-200 bg-slate-50 p-4"
    >
      <p class="text-lg font-semibold text-slate-900 first-letter:uppercase">
        {{ when }}
      </p>
      <p data-testid="confirm-summary" class="text-base text-slate-800">
        {{ summary }}
      </p>
      <p v-if="address" class="text-base text-slate-800">
        {{ t('BOOKING_V2.ADDRESS', { address }) }}
      </p>
      <ZoneNote v-if="isOtherClock" />
    </div>
    <form
      class="flex flex-col gap-5"
      novalidate
      @submit.prevent="submitBooking"
    >
      <ChoiceCards
        v-if="options.length > 1"
        v-model="locationType"
        name="booking-location"
        :legend="t('BOOKING_V2.DETAILS.LOCATION_TITLE')"
        :options="options"
      />
      <TextField
        v-if="askName"
        id="booking-name"
        v-model="form.name"
        :label="t('BOOKING_V2.DETAILS.NAME')"
        :error="fieldErrors.name"
        autocomplete="name"
        required
      />
      <PhoneField
        v-if="askPhone"
        id="booking-phone"
        v-model:country="form.countryCode"
        v-model:national="form.phone"
        :label="t('BOOKING_V2.CONFIRM.NEW_NUMBER')"
        :error="fieldErrors.phone"
      />
      <TextField
        v-if="emailRequired || fieldErrors.email"
        id="booking-email"
        v-model="form.email"
        type="email"
        autocomplete="email"
        inputmode="email"
        :label="t('BOOKING_V2.DETAILS.EMAIL_REQUIRED')"
        :hint="t('BOOKING_V2.DETAILS.EMAIL_HINT')"
        :error="fieldErrors.email"
        required
      />
      <FormFooter :submit-label="t('BOOKING_V2.DETAILS.CONFIRM')" />
    </form>
    <div class="flex flex-col gap-2">
      <ActionButton
        v-if="canChangePhone"
        variant="secondary"
        @click="startPhoneChange"
      >
        {{ t('BOOKING_V2.CONFIRM.CHANGE_NUMBER') }}
      </ActionButton>
      <ActionButton variant="ghost" @click="goBack">
        {{ t('BOOKING_V2.BACK') }}
      </ActionButton>
    </div>
  </section>
</template>
