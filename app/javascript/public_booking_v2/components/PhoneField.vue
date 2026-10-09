<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  caretAfterDigits,
  formatNational,
  normalizeNational,
  onlyDigits,
} from '../helpers/phone';

// WhatsApp: código do país (padrão +55) e o número com DDD, formatado enquanto a pessoa digita. Guardamos só os
// dígitos que vão para o servidor: o que aparece é o que é enviado. Colado com "+55", o código sai do número.
// Formatação com métodos de string (sem regex). `error` é a chave de tradução do erro.
const props = defineProps({
  id: { type: String, required: true },
  label: { type: String, required: true },
  error: { type: String, default: '' },
});

const country = defineModel('country', { type: String, default: '55' });
const national = defineModel('national', { type: String, default: '' });

const { t } = useI18n();

const display = computed(() => formatNational(national.value, country.value));
const errorText = computed(() => (props.error ? t(props.error) : ''));
const describedBy = computed(() =>
  [`${props.id}-hint`, props.error && `${props.id}-error`]
    .filter(Boolean)
    .join(' ')
);

const onCountryInput = event => {
  const digits = onlyDigits(event.target.value).slice(0, 3);
  country.value = digits;
  event.target.value = `+${digits}`;
};

const onNationalInput = event => {
  const input = event.target;
  const raw = input.value;
  const pasted = event.inputType === 'insertFromPaste';
  const digits = normalizeNational(raw, country.value, { pasted });
  const typedBefore = onlyDigits(
    raw.slice(0, input.selectionStart ?? raw.length)
  );
  const caretDigits = pasted
    ? digits.length
    : Math.min(typedBefore.length, digits.length);

  national.value = digits;
  const formatted = formatNational(digits, country.value);
  input.value = formatted;
  if (document.activeElement === input) {
    const position = caretAfterDigits(formatted, caretDigits);
    input.setSelectionRange(position, position);
  }
};
</script>

<template>
  <fieldset class="flex flex-col gap-1">
    <legend class="mb-1 text-base font-medium text-slate-800">
      {{ label }}
    </legend>
    <div class="flex gap-2">
      <label :for="`${id}-country`" class="sr-only">
        {{ t('BOOKING_V2.DETAILS.COUNTRY') }}
      </label>
      <input
        :id="`${id}-country`"
        :value="`+${country}`"
        type="tel"
        inputmode="tel"
        autocomplete="tel-country-code"
        class="min-h-12 w-20 shrink-0 rounded-xl border-2 border-slate-300 bg-white px-3 py-3 text-base text-slate-900 focus:border-[var(--brand)] focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)]"
        @input="onCountryInput"
      />
      <label :for="id" class="sr-only">{{ label }}</label>
      <input
        :id="id"
        :value="display"
        type="tel"
        inputmode="tel"
        autocomplete="tel-national"
        :aria-invalid="error ? 'true' : undefined"
        :aria-describedby="describedBy"
        class="min-h-12 w-full min-w-0 rounded-xl border-2 bg-white px-4 py-3 text-base text-slate-900 focus:border-[var(--brand)] focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)]"
        :class="error ? 'border-red-600' : 'border-slate-300'"
        @input="onNationalInput"
      />
    </div>
    <p :id="`${id}-hint`" class="text-base text-slate-600">
      {{ t('BOOKING_V2.DETAILS.PHONE_HINT') }}
    </p>
    <p
      v-if="error"
      :id="`${id}-error`"
      class="text-base font-medium text-red-700"
    >
      {{ errorText }}
    </p>
  </fieldset>
</template>
