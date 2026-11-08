<script setup>
import { computed, ref } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ExcluirContatoDialogo from 'dashboard/routes/dashboard/crm/components/excluir/ExcluirContatoDialogo.vue';

const props = defineProps({
  selectedContact: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['goToContactsList']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();

const dialogRef = ref(null);
const excluirComCardsRef = ref(null);

// #2096 — com o CRM, os cards do contato não ficam mais com o dado pessoal dele. O administrador, com a flag
// crm_arquivados, escolhe se eles saem junto ou ficam como "Cliente removido" (ExcluirContatoDialogo). Quem exclui
// pela janela de sempre deixa os cards como "Cliente removido", e a janela avisa.
const currentAccountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');
const currentRole = useMapGetter('getCurrentRole');
const flagLigada = flag =>
  getAccount.value(currentAccountId.value)?.features?.[flag] === true;
const crmLigado = computed(() => flagLigada(FEATURE_FLAGS.CRM));
const escolheOsCards = computed(
  () =>
    crmLigado.value &&
    flagLigada(FEATURE_FLAGS.CRM_ARQUIVADOS) &&
    currentRole.value === 'administrator'
);
const contatoId = () => route.params.contactId || props.selectedContact?.id;
const contato = computed(() => ({
  id: contatoId(),
  name: props.selectedContact?.name || '',
}));
const descricao = computed(() =>
  [
    t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.DESCRIPTION'),
    t('APAGAR_CONTATO.UM'),
    crmLigado.value ? t('CRM_EXCLUIR.CONTATO.NOTA_CARDS') : '',
  ]
    .filter(Boolean)
    .join(' ')
);

const deleteContact = async id => {
  if (!id) return;

  try {
    await store.dispatch('contacts/delete', id);
    useAlert(t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.API.ERROR_MESSAGE'));
  }
};

const handleDialogConfirm = async () => {
  emit('goToContactsList');
  await deleteContact(contatoId());
  dialogRef.value?.close();
};

const aoExcluirComCards = ({ nome, cards, modo }) => {
  emit('goToContactsList');
  if (!cards) {
    useAlert(t('CRM_EXCLUIR.CONTATO.EXCLUIDO', { nome }));
    return;
  }
  const chave =
    modo === 'delete'
      ? 'CRM_EXCLUIR.CONTATO.EXCLUIDO_APAGADOS'
      : 'CRM_EXCLUIR.CONTATO.EXCLUIDO_MANTIDOS';
  useAlert(t(chave, { nome, count: cards }, cards));
};

// Quem chama abre por `dialogRef.open()`; com a escolha dos cards, abre a janela nova no lugar da de sempre.
const abrir = () => {
  if (escolheOsCards.value) excluirComCardsRef.value?.open();
  else dialogRef.value?.open();
};
const fechar = () => {
  dialogRef.value?.close();
  excluirComCardsRef.value?.close();
};

defineExpose({ dialogRef: { open: abrir, close: fechar } });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.TITLE')"
    :description="descricao"
    :confirm-button-label="t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.CONFIRM')"
    @confirm="handleDialogConfirm"
  />
  <ExcluirContatoDialogo
    v-if="escolheOsCards"
    ref="excluirComCardsRef"
    :contato="contato"
    @excluido="aoExcluirComCards"
  />
</template>
