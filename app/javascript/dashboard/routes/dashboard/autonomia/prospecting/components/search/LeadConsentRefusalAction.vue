<script setup>
// "Não quer ser contatado" e "Desfazer: pode ser contatado" no painel do lead
// (chat#713). Os dois pedem confirmação. A recusa fica no lead, sem mudar o
// status, e o servidor a leva aos contatos que o número ou o e-mail alcançam.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ConfirmModal from 'dashboard/components/widgets/modal/ConfirmationModal.vue';
import { isLeadConsentRefused } from '../../utils/leadCrmPresence';

const props = defineProps({
  lead: { type: Object, required: true },
  refuse: { type: Function, required: true },
  withdraw: { type: Function, required: true },
});

const { t } = useI18n();
const confirmModal = ref(null);
const saving = ref(false);

const refused = computed(() => isLeadConsentRefused(props.lead));
const prefix = computed(
  () => `PROSPECTING.CONSENT_REFUSAL.${refused.value ? 'WITHDRAW' : 'REFUSE'}`
);

const confirmAndSave = async () => {
  if (saving.value) return;
  const save = refused.value ? props.withdraw : props.refuse;
  const confirmed = await confirmModal.value?.showConfirmation();
  if (!confirmed) return;

  saving.value = true;
  try {
    await save(props.lead);
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <button
    type="button"
    class="h-9 rounded-md border border-n-weak px-3 text-sm font-medium hover:bg-n-solid-2 disabled:cursor-not-allowed disabled:opacity-60"
    :class="refused ? 'text-n-slate-12' : 'text-n-amber-11'"
    :disabled="saving"
    @click="confirmAndSave"
  >
    {{ t(`${prefix}.ACTION`) }}
  </button>
  <ConfirmModal
    ref="confirmModal"
    :title="t(`${prefix}.CONFIRM_TITLE`)"
    :description="t(`${prefix}.CONFIRM_DESCRIPTION`)"
    :confirm-label="t(`${prefix}.CONFIRM`)"
    :cancel-label="t('PROSPECTING.CONSENT_REFUSAL.CANCEL')"
  />
</template>
