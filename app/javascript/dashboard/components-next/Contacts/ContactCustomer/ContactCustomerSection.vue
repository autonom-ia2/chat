<script setup>
// Lead ou cliente (#1144): ganho num funil de venda já promove o contato; aqui a equipe marca quem comprou de outro
// jeito, ou desfaz um engano. Sempre com confirmação, pela rota própria.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, fromUnixTime } from 'date-fns';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { dateFnsLocaleFor } from 'shared/helpers/dateFnsLocale';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  readOnly: { type: Boolean, default: false },
  contact: {
    type: Object,
    required: true,
  },
});

const PREFIX = 'CONTACTS_LAYOUT.DETAILS.CUSTOMER';

const { t, locale } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const isSaving = ref(false);

const isCustomer = computed(() => props.contact?.contactType === 'customer');

const customerSince = computed(() => {
  if (!isCustomer.value || !props.contact?.customerSince) return '';
  return format(fromUnixTime(props.contact.customerSince), 'P', {
    locale: dateFnsLocaleFor(locale.value),
  });
});

const dialogKey = computed(() =>
  isCustomer.value ? `${PREFIX}.UNDO_DIALOG` : `${PREFIX}.MARK_DIALOG`
);

const openDialog = () => dialogRef.value?.open();

const confirmChange = async () => {
  if (props.readOnly) return;
  const customer = !isCustomer.value;
  isSaving.value = true;
  try {
    await store.dispatch('contacts/setCustomer', {
      id: props.contact.id,
      customer,
    });
    useAlert(t(`${PREFIX}.API.${customer ? 'MARK_SUCCESS' : 'UNDO_SUCCESS'}`));
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
        v-if="isCustomer"
        data-test="customer-badge"
        class="inline-flex items-center gap-1.5 px-2 py-1 text-sm font-medium rounded-md w-fit bg-n-teal-3 text-n-teal-11"
      >
        <span class="i-lucide-badge-check size-4" aria-hidden="true" />
        {{
          customerSince
            ? t(`${PREFIX}.SINCE`, { date: customerSince })
            : t(`${PREFIX}.BADGE`)
        }}
      </span>
      <span class="text-sm text-n-slate-11">
        {{ t(`${PREFIX}.DESCRIPTION`) }}
      </span>
    </div>
    <Button
      v-if="!readOnly"
      data-test="customer-action"
      :label="isCustomer ? t(`${PREFIX}.UNDO`) : t(`${PREFIX}.MARK`)"
      size="sm"
      :color="isCustomer ? 'slate' : 'teal'"
      :is-loading="isSaving"
      :disabled="isSaving"
      @click="openDialog"
    />
    <Dialog
      v-if="!readOnly"
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
