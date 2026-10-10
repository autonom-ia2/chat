<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { kindsWithoutTemplate, presetFor } from '../bookingNotices';
import { formatMinutes } from '../bookingFormat';

// Os avisos no WhatsApp em uma frase, na prévia (#1192): quando o cliente é
// avisado, por qual número e até quando pode mudar. Não promete o que não
// sai: aviso sem mensagem pronta e número WAHA só alcançam quem falou com a
// empresa nas últimas 24 horas (J2-A6). "Alterar" volta ao passo dos avisos;
// quem só vê não tem o botão.
const props = defineProps({
  form: { type: Object, required: true },
  inboxOptions: { type: Array, default: () => [] },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['alter']);
const { t } = useI18n();

const inbox = computed(() =>
  props.inboxOptions.find(item => item.id === props.form.noticeInboxId)
);
const inboxName = computed(() => inbox.value?.name || '');

const sentence = computed(() => {
  if (!props.form.noticeInboxId) return t('BOOKING.PREVIEW.NOTICES_OFF');
  const when = t(
    `BOOKING.NOTICES.PRESETS.${presetFor(props.form.noticePreset).key.toUpperCase()}.SUMMARY`
  );
  return inboxName.value
    ? t('BOOKING.PREVIEW.NOTICES_ON', { when, inbox: inboxName.value })
    : t('BOOKING.PREVIEW.NOTICES_ON_NO_NAME', { when });
});

// Ressalva da janela de 24 horas, quando ela vale para algum aviso.
const windowNote = computed(() => {
  if (!props.form.noticeInboxId || !inbox.value) return '';
  if (inbox.value.provider === 'waha')
    return t('BOOKING.PREVIEW.NOTICES_WINDOW_ONLY');
  const missing = kindsWithoutTemplate(props.form, inbox.value)
    .map(kind => t(`BOOKING.NOTICES.KINDS.${kind.toUpperCase()}`))
    .join(', ');
  return missing
    ? t('BOOKING.NOTICES.MISSING_TEMPLATES', { kinds: missing })
    : '';
});

const deadline = computed(() =>
  props.form.cancelUntilMinutes
    ? t('BOOKING.PREVIEW.CANCEL_UNTIL', {
        value: formatMinutes(t, props.form.cancelUntilMinutes),
      })
    : t('BOOKING.PREVIEW.CANCEL_ANYTIME')
);
</script>

<template>
  <div
    data-notices-summary
    class="flex flex-wrap items-start justify-between gap-3 p-5 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
  >
    <div class="flex flex-col flex-1 gap-1 min-w-60">
      <p class="m-0 text-base text-n-slate-12">
        <span
          class="i-lucide-message-circle me-1 size-4 align-[-2px] text-n-teal-11"
          aria-hidden="true"
        />
        {{ sentence }}
      </p>
      <p
        v-if="windowNote"
        data-notices-window
        class="m-0 text-base text-n-amber-12"
      >
        {{ windowNote }}
      </p>
      <p class="m-0 text-base text-n-slate-11">{{ deadline }}</p>
    </div>
    <button
      v-if="canManage"
      type="button"
      data-notices-alter
      class="inline-flex items-center gap-2 min-h-11 px-4 rounded-xl text-base font-semibold text-n-blue-11 ring-1 ring-inset ring-n-blue-7 hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :aria-label="t('BOOKING.PREVIEW.NOTICES_ALTER')"
      @click="emit('alter')"
    >
      <span class="i-lucide-pencil size-4" aria-hidden="true" />
      {{ t('BOOKING.PREVIEW.ALTER') }}
    </button>
  </div>
</template>
