<script setup>
// "Enviar teste" field of the e-mail editor (#1093, decision of 07/10/2026): any typed address,
// up to 5, one per line (comma or space also work). Starts with the logged-in user's address.
// The page sends; this form only checks what was typed and says what is wrong, in one line.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import {
  parseTestRecipients,
  testRecipientsProblem,
} from 'dashboard/routes/dashboard/campaigns/pages/emailTestSend';

const props = defineProps({
  defaultEmail: { type: String, default: '' },
  isSending: { type: Boolean, default: false },
  // The server refusal, already translated by the page.
  errorMessage: { type: String, default: '' },
});

const emit = defineEmits(['send', 'cancel']);

const BUILDER = 'CAMPAIGN.EMAIL_CAMPAIGN.BUILDER';
const FIELD_ID = 'email-test-send-recipients';
const MAX_FIELD_LENGTH = 600;
const { t } = useI18n();

const text = ref(props.defaultEmail);
const problem = ref(null);

const shownError = computed(() =>
  problem.value
    ? t(problem.value.key, problem.value.params)
    : props.errorMessage
);

const onInput = value => {
  text.value = value;
  problem.value = null;
};

const submit = () => {
  const parsed = parseTestRecipients(text.value);
  problem.value = testRecipientsProblem(parsed);
  if (problem.value) return;
  emit('send', parsed.emails);
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <TextArea
      :id="FIELD_ID"
      :model-value="text"
      :label="t(`${BUILDER}.SEND_TEST_EMAIL_LABEL`)"
      :placeholder="t(`${BUILDER}.SEND_TEST_EMAIL_PLACEHOLDER`)"
      :max-length="MAX_FIELD_LENGTH"
      :message-type="shownError ? 'error' : 'info'"
      auto-height
      min-height="5rem"
      custom-text-area-class="!text-base sm:!text-sm"
      @update:model-value="onInput"
    />
    <p
      v-if="shownError"
      class="m-0 break-words text-sm text-n-ruby-11"
      role="alert"
      data-test="test-send-error"
    >
      {{ shownError }}
    </p>
    <p v-else class="m-0 text-sm text-n-slate-11">
      {{ t(`${BUILDER}.SEND_TEST_EMAIL_HINT`) }}
    </p>
    <div class="flex justify-end gap-2">
      <Button
        type="button"
        :label="t(`${BUILDER}.CANCEL`)"
        color="slate"
        variant="ghost"
        class="!min-h-11"
        data-test="test-send-cancel"
        @click="emit('cancel')"
      />
      <Button
        type="button"
        :label="t(`${BUILDER}.SEND_TEST_SUBMIT`)"
        color="blue"
        class="!min-h-11"
        :is-loading="isSending"
        :disabled="isSending"
        data-test="test-send-submit"
        @click="submit"
      />
    </div>
  </div>
</template>
