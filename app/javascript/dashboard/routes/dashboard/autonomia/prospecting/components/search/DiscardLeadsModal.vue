<script setup>
// Janela "Descartar" (#732, item 10), a mesma no painel do lead e na seleção
// da busca. O motivo é obrigatório, como no servidor (LeadDiscard): uma das
// escolhas prontas ou o texto de "Outro motivo". Quem descarta é a função
// `discard` do contexto, que troca os leads na tela.
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';

const props = defineProps({
  leads: { type: Array, required: true },
  discard: { type: Function, required: true },
});

const emit = defineEmits(['close', 'discarded']);

// O mesmo teto do servidor (LeadDiscard::MAX_REASON_LENGTH).
const MAX_REASON_LENGTH = 255;
const OTHER = 'OTHER';
const REASON_KEYS = [
  'NO_INTEREST',
  'OUT_OF_PROFILE',
  'ALREADY_CUSTOMER',
  'WRONG_DATA',
  'CLOSED',
  OTHER,
];

// A janela cobre a tela inteira, inclusive o canto do lançador do Guia (#646).
useFixedPanelPresence(computed(() => true));

const { t } = useI18n();
const titleId = useId();
const reasonKey = ref('');
const otherReason = ref('');
const submitting = ref(false);
const error = ref('');

const reasonChoices = computed(() =>
  REASON_KEYS.map(key => ({
    value: key,
    label: t(`PROSPECTING.DISCARD.REASONS.${key}`),
  }))
);
const reason = computed(() => {
  if (!reasonKey.value) return '';
  if (reasonKey.value === OTHER) return otherReason.value.trim();
  return t(`PROSPECTING.DISCARD.REASONS.${reasonKey.value}`);
});
const canSubmit = computed(() => Boolean(reason.value) && !submitting.value);

const submit = async () => {
  if (!canSubmit.value) return;

  submitting.value = true;
  error.value = '';
  try {
    const payload = await props.discard(
      props.leads.map(lead => lead.id),
      reason.value
    );
    useAlert(t('PROSPECTING.DISCARD.DONE', { count: props.leads.length }));
    emit('discarded', payload);
  } catch (e) {
    error.value = e?.response?.data?.error || t('PROSPECTING.DISCARD.ERROR');
  } finally {
    submitting.value = false;
  }
};

const close = () => {
  if (!submitting.value) emit('close');
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-n-slate-12/30 px-4"
    @click.self="close"
  >
    <section
      role="dialog"
      aria-modal="true"
      :aria-labelledby="titleId"
      class="grid max-h-[90vh] w-full max-w-md gap-4 overflow-y-auto rounded-lg border border-n-weak bg-n-solid-1 p-5 shadow-xl"
    >
      <header class="flex items-start justify-between gap-3">
        <h2 :id="titleId" class="text-base font-semibold text-n-slate-12">
          {{ t('PROSPECTING.DISCARD.TITLE') }}
        </h2>
        <button
          type="button"
          class="flex size-11 shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-solid-2 disabled:cursor-not-allowed disabled:opacity-60"
          :aria-label="t('PROSPECTING.DISCARD.CLOSE')"
          :disabled="submitting"
          @click="close"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
        </button>
      </header>

      <p class="text-sm text-n-slate-11">
        {{ t('PROSPECTING.DISCARD.DESCRIPTION', { count: leads.length }) }}
      </p>

      <div class="grid gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.DISCARD.REASON') }}
        </span>
        <ChoiceSelect
          v-model="reasonKey"
          :options="reasonChoices"
          :aria-label="t('PROSPECTING.DISCARD.REASON')"
          :disabled="submitting"
        />
      </div>

      <label v-if="reasonKey === OTHER" class="grid gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.DISCARD.OTHER_REASON') }}
        </span>
        <input
          v-model="otherReason"
          type="text"
          :maxlength="MAX_REASON_LENGTH"
          :disabled="submitting"
          class="h-11 rounded-md border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12"
        />
      </label>

      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>

      <footer class="flex flex-wrap justify-end gap-2">
        <button
          type="button"
          class="h-11 rounded-md border border-n-weak px-4 text-sm font-medium text-n-slate-12 hover:bg-n-solid-2 disabled:opacity-60"
          :disabled="submitting"
          @click="close"
        >
          {{ t('PROSPECTING.DISCARD.CANCEL') }}
        </button>
        <button
          type="button"
          data-test="discard-submit"
          class="h-11 rounded-md bg-n-ruby-9 px-4 text-sm font-semibold text-white disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="!canSubmit"
          @click="submit"
        >
          {{
            submitting
              ? t('PROSPECTING.DISCARD.SUBMITTING')
              : t('PROSPECTING.DISCARD.SUBMIT')
          }}
        </button>
      </footer>
    </section>
  </div>
</template>
