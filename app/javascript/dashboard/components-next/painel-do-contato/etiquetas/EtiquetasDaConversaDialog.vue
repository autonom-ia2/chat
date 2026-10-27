<script setup>
// #2202 (PR 3) — "Etiquetas desta conversa": a escolha de etiquetas da conversa
// aberta, pelo ⋯ do topo e pelo bloco "Etiquetas" do painel. A lista é a mesma
// do painel antigo (LabelDropdown), com as mesmas actions (useConversationLabels):
// tocar numa etiqueta põe ou tira na hora.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  getUserPermissions,
  hasPermissions,
} from 'dashboard/helper/permissionsHelper';
import { useConversationLabels } from 'dashboard/composables/useConversationLabels';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';

// A lista do painel antigo, com alvos de 44 px e sem o atalho "L" (que só vale
// no painel antigo).
const { t } = useI18n();
const store = useStore();
const dialogo = ref(null);
const eu = useMapGetter('getCurrentUser');
const contaId = useMapGetter('getCurrentAccountId');
// Como no painel antigo (LabelBox): criar etiqueta é de quem administra etiquetas.
const podeCriar = computed(() =>
  hasPermissions(
    ['administrator', 'label_manage'],
    getUserPermissions(eu.value, contaId.value)
  )
);
const { savedLabels, accountLabels, activeLabels, onUpdateLabels } =
  useConversationLabels();
// As etiquetas que a conversa já tem vêm primeiro: a pessoa vê o que tem antes
// de rolar a lista.
const etiquetasEmOrdem = computed(() =>
  accountLabels.value.toSorted(
    (a, b) =>
      Number(savedLabels.value.includes(b.title)) -
      Number(savedLabels.value.includes(a.title))
  )
);

const salvar = async titulos => {
  await onUpdateLabels(titulos);
  if (store.getters['conversationLabels/getUIFlags']?.isError)
    useAlert(t('PAINEL_DO_CONTATO.ETIQUETAS.ERRO'));
};
const titulosAtivos = () => activeLabels.value.map(label => label.title);
const por = label => salvar([...titulosAtivos(), label.title]);
const tirar = titulo => salvar(titulosAtivos().filter(item => item !== titulo));

const abrir = () => dialogo.value?.open();
const fechar = () => dialogo.value?.close();

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    data-dialogo-etiquetas
    :title="t('PAINEL_DO_CONTATO.ETIQUETAS.DIALOGO_TITULO')"
    :description="t('PAINEL_DO_CONTATO.ETIQUETAS.DIALOGO_FRASE')"
    width="sm"
  >
    <div
      class="w-full [&>div]:!max-h-80 [&_.search-input]:!min-h-11 [&_li_button]:!min-h-11 [&_kbd]:!hidden"
    >
      <LabelDropdown
        :account-labels="etiquetasEmOrdem"
        :selected-labels="savedLabels"
        :allow-creation="podeCriar"
        @add="por"
        @remove="tirar"
      />
    </div>
    <template #footer>
      <div class="flex justify-end">
        <Button
          type="button"
          :label="t('PAINEL_DO_CONTATO.ETIQUETAS.PRONTO')"
          class="!min-h-11"
          @click="fechar"
        />
      </div>
    </template>
  </Dialog>
</template>
