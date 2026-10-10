<script setup>
import { nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import { testInviteProblem } from '../bookingNotices';

// "Testar no meu WhatsApp" (#1192, J3-A11): a pessoa digita o número dela e
// recebe, pelo número de avisos da página, um link igual ao do cliente. É uma
// ação secundária da prévia: o botão principal continua sendo o do rodapé.
const props = defineProps({
  pageId: { type: Number, required: true },
});

const { t } = useI18n();
const fieldId = useId();
const hintId = useId();

const open = ref(false);
const phone = ref('');
const sending = ref(false);
// '' | 'SENT' | chave de BOOKING.NOTICES.TEST.ERRORS
const result = ref('');
const input = ref(null);

const BUTTON =
  'inline-flex items-center gap-2 min-h-11 px-4 rounded-xl text-base font-medium text-n-slate-12 bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:ring-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60 disabled:cursor-not-allowed';

const start = async () => {
  open.value = true;
  result.value = '';
  await nextTick();
  input.value?.focus();
};

const send = async () => {
  if (!phone.value.trim()) {
    result.value = 'INVALID_PHONE';
    return;
  }
  sending.value = true;
  result.value = '';
  try {
    await BookingPagesAPI.testInvite(props.pageId, phone.value.trim());
    result.value = 'SENT';
  } catch (failure) {
    result.value = testInviteProblem(failure?.response?.data);
  } finally {
    sending.value = false;
  }
};
</script>

<template>
  <div data-test-invite class="flex flex-col gap-3">
    <button
      v-if="!open"
      type="button"
      data-test-start
      :class="BUTTON"
      @click="start"
    >
      <span class="i-lucide-message-circle size-4" aria-hidden="true" />
      {{ t('BOOKING.NOTICES.TEST.BUTTON') }}
    </button>
    <form
      v-else
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
      @submit.prevent="send"
    >
      <label :for="fieldId" class="text-base font-semibold text-n-slate-12">
        {{ t('BOOKING.NOTICES.TEST.PHONE_LABEL') }}
      </label>
      <p :id="hintId" class="m-0 text-base text-n-slate-11">
        {{ t('BOOKING.NOTICES.TEST.PHONE_HINT') }}
      </p>
      <div class="flex flex-wrap gap-2">
        <input
          :id="fieldId"
          ref="input"
          v-model="phone"
          data-test-phone
          type="tel"
          inputmode="tel"
          autocomplete="tel"
          :aria-describedby="hintId"
          :aria-invalid="result === 'INVALID_PHONE' ? 'true' : undefined"
          :placeholder="t('BOOKING.NOTICES.TEST.PHONE_PLACEHOLDER')"
          class="flex-1 min-w-48 min-h-11 px-4 mb-0 text-base rounded-xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        />
        <button
          type="submit"
          data-test-send
          :disabled="sending"
          :class="BUTTON"
        >
          <span
            class="size-4"
            :class="
              sending ? 'i-lucide-loader-circle animate-spin' : 'i-lucide-send'
            "
            aria-hidden="true"
          />
          {{ t('BOOKING.NOTICES.TEST.SEND') }}
        </button>
      </div>
      <p
        v-if="result === 'SENT'"
        data-test-result="SENT"
        role="status"
        class="m-0 text-base text-n-teal-11"
      >
        {{ t('BOOKING.NOTICES.TEST.SENT') }}
      </p>
      <p
        v-else-if="result"
        :data-test-result="result"
        role="alert"
        class="m-0 text-base text-n-ruby-11"
      >
        {{ t(`BOOKING.NOTICES.TEST.ERRORS.${result}`) }}
      </p>
    </form>
  </div>
</template>
