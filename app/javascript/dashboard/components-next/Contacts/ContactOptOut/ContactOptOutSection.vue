<script setup>
// Recusa de mensagens ativas no contato (chat#713): mostra o selo com data e origem, e marca ou desfaz pela rota
// própria, sempre com confirmação. Resposta a quem escreve não muda; só campanhas e follow-ups automáticos respeitam.
// Aqui só se desfaz a recusa manual: a da Prospecção e a do descadastro de e-mail saem na origem, e a tela diz onde.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, fromUnixTime } from 'date-fns';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { dateFnsLocaleFor } from 'shared/helpers/dateFnsLocale';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  contact: {
    type: Object,
    required: true,
  },
});

const PREFIX = 'CONTACTS_LAYOUT.DETAILS.OPT_OUT';
const KNOWN_SOURCES = ['prospecting', 'email_unsubscribe', 'manual'];
const ORIGIN_HINT_SOURCES = ['prospecting', 'email_unsubscribe'];

const { t, locale } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const isSaving = ref(false);

const isOptedOut = computed(() => Boolean(props.contact?.optedOutAt));

const optedOutDate = computed(() => {
  if (!isOptedOut.value) return '';
  return format(fromUnixTime(props.contact.optedOutAt), 'P', {
    locale: dateFnsLocaleFor(locale.value),
  });
});

const sourceLabel = computed(() => {
  const source = props.contact?.optOutSource;
  if (!KNOWN_SOURCES.includes(source)) return t(`${PREFIX}.SOURCES.UNKNOWN`);
  return t(`${PREFIX}.SOURCES.${source.toUpperCase()}`);
});

const canUndo = computed(
  () => isOptedOut.value && props.contact?.optOutSource === 'manual'
);

const showAction = computed(() => !isOptedOut.value || canUndo.value);

const originHint = computed(() => {
  const source = props.contact?.optOutSource;
  if (!isOptedOut.value || !ORIGIN_HINT_SOURCES.includes(source)) return '';
  return t(`${PREFIX}.ORIGIN_HINT.${source.toUpperCase()}`);
});

const dialogKey = computed(() =>
  isOptedOut.value ? `${PREFIX}.UNDO_DIALOG` : `${PREFIX}.MARK_DIALOG`
);

const openDialog = () => dialogRef.value?.open();

// Desfazer a manual pode deixar a recusa de pé, com a origem que ainda vale (por exemplo, o e-mail descadastrado).
const resultKey = (optedOut, payload) => {
  if (optedOut) return 'MARK_SUCCESS';
  return payload?.opted_out_at ? 'UNDO_KEPT' : 'UNDO_SUCCESS';
};

const confirmChange = async () => {
  const optedOut = !isOptedOut.value;
  isSaving.value = true;
  try {
    const payload = await store.dispatch('contacts/setOptOut', {
      id: props.contact.id,
      optedOut,
    });
    useAlert(t(`${PREFIX}.API.${resultKey(optedOut, payload)}`));
    dialogRef.value?.close();
  } catch {
    useAlert(t(`${PREFIX}.API.ERROR`));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div
    class="flex flex-col items-start w-full gap-4 pt-6 border-t border-n-strong"
  >
    <div class="flex flex-col gap-2">
      <h6 class="text-base font-medium text-n-slate-12">
        {{ t(`${PREFIX}.TITLE`) }}
      </h6>
      <span
        v-if="isOptedOut"
        data-test="opt-out-badge"
        class="inline-flex items-center gap-1.5 px-2 py-1 text-sm font-medium rounded-md w-fit bg-n-amber-3 text-n-amber-11"
      >
        <span class="i-lucide-bell-off size-4" aria-hidden="true" />
        {{ t(`${PREFIX}.BADGE`) }}
      </span>
      <span
        v-if="isOptedOut"
        data-test="opt-out-details"
        class="text-sm text-n-slate-11"
      >
        {{ t(`${PREFIX}.SINCE`, { date: optedOutDate, source: sourceLabel }) }}
      </span>
      <span
        v-if="originHint"
        data-test="opt-out-origin-hint"
        class="text-sm text-n-slate-11"
      >
        {{ originHint }}
      </span>
      <span class="text-sm text-n-slate-11">
        {{ t(`${PREFIX}.DESCRIPTION`) }}
      </span>
    </div>
    <Button
      v-if="showAction"
      data-test="opt-out-action"
      :label="isOptedOut ? t(`${PREFIX}.UNDO`) : t(`${PREFIX}.MARK`)"
      size="sm"
      :color="isOptedOut ? 'slate' : 'amber'"
      :is-loading="isSaving"
      :disabled="isSaving"
      @click="openDialog"
    />
    <Dialog
      v-if="showAction"
      ref="dialogRef"
      type="alert"
      :title="t(`${dialogKey}.TITLE`)"
      :description="t(`${dialogKey}.DESCRIPTION`)"
      :confirm-button-label="t(`${dialogKey}.CONFIRM`)"
      :is-loading="isSaving"
      @confirm="confirmChange"
    />
  </div>
</template>
