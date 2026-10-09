<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { whenLabel } from '../helpers/datetime';
import {
  locationHint,
  locationName,
  locationOptions,
} from '../helpers/locations';
import ActionButton from './ActionButton.vue';
import BrandHeader from './BrandHeader.vue';
import ChoiceCards from './ChoiceCards.vue';
import FormFooter from './FormFooter.vue';
import PhoneField from './PhoneField.vue';
import TextField from './TextField.vue';

// Seus dados (J2): só nome e WhatsApp; e-mail opcional, obrigatório quando o local exige (Meet/Teams). Com um local
// só, ele aparece escrito (e o endereço, se for presencial) antes de confirmar.
const {
  page,
  form,
  fieldErrors,
  locations,
  locationType,
  selectedLocation,
  emailRequired,
  selectedSlot,
  clientZone,
  goBack,
  submitBooking,
} = useFlow();
const { t, locale } = useI18n();

const subtitle = computed(() =>
  selectedSlot.value
    ? whenLabel(selectedSlot.value, locale.value, clientZone)
    : ''
);
const options = computed(() => locationOptions(locations.value, t));
const onlyLocation = computed(() =>
  options.value.length === 1 ? selectedLocation.value : null
);
</script>

<template>
  <section class="flex flex-col gap-6" aria-labelledby="step-heading">
    <BrandHeader :page="page" :subtitle="subtitle" />
    <h1
      id="step-heading"
      data-step-heading
      tabindex="-1"
      class="text-2xl font-bold text-slate-900 focus:outline-none"
    >
      {{ t('BOOKING_V2.DETAILS.TITLE') }}
    </h1>
    <div
      v-if="onlyLocation"
      data-testid="only-location"
      class="flex flex-col gap-1 rounded-2xl border-2 border-slate-200 bg-slate-50 p-4"
    >
      <p class="text-base font-semibold text-slate-900">
        {{ locationName(onlyLocation, t) }}
      </p>
      <p class="text-base text-slate-800">
        {{ locationHint(onlyLocation, t) }}
      </p>
    </div>
    <form
      class="flex flex-col gap-5"
      novalidate
      @submit.prevent="submitBooking"
    >
      <TextField
        id="booking-name"
        v-model="form.name"
        :label="t('BOOKING_V2.DETAILS.NAME')"
        :error="fieldErrors.name"
        autocomplete="name"
        required
      />
      <PhoneField
        id="booking-phone"
        v-model:country="form.countryCode"
        v-model:national="form.phone"
        :label="t('BOOKING_V2.DETAILS.PHONE')"
        :error="fieldErrors.phone"
      />
      <ChoiceCards
        v-if="options.length > 1"
        v-model="locationType"
        name="booking-location"
        :legend="t('BOOKING_V2.DETAILS.LOCATION_TITLE')"
        :options="options"
      />
      <TextField
        id="booking-email"
        v-model="form.email"
        type="email"
        autocomplete="email"
        inputmode="email"
        :label="
          emailRequired
            ? t('BOOKING_V2.DETAILS.EMAIL_REQUIRED')
            : t('BOOKING_V2.DETAILS.EMAIL_OPTIONAL')
        "
        :hint="emailRequired ? t('BOOKING_V2.DETAILS.EMAIL_HINT') : ''"
        :error="fieldErrors.email"
        :required="emailRequired"
      />
      <FormFooter :submit-label="t('BOOKING_V2.DETAILS.CONFIRM')" />
    </form>
    <ActionButton variant="ghost" @click="goBack">
      {{ t('BOOKING_V2.BACK') }}
    </ActionButton>
  </section>
</template>
