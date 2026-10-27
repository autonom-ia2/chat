<script setup>
// #2202 (PR 3) — "Etiquetas desta conversa": a escolha de etiquetas da conversa
// aberta, pelo ⋯ do topo e pelo bloco "Etiquetas" do painel. A lista é a mesma
// do painel antigo (LabelDropdown), com a mesma action (useConversationLabels):
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
import Spinner from 'shared/components/Spinner.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import AddLabelModal from 'dashboard/routes/dashboard/settings/labels/AddLabel.vue';

const { t } = useI18n();
const store = useStore();
const dialogo = ref(null);
const eu = useMapGetter('getCurrentUser');
const contaId = useMapGetter('getCurrentAccountId');
const flags = useMapGetter('conversationLabels/getUIFlags');
// Como no painel antigo (LabelBox): criar etiqueta é de quem administra etiquetas.
const podeCriar = computed(() =>
  hasPermissions(
    ['administrator', 'label_manage'],
    getUserPermissions(eu.value, contaId.value)
  )
);
const { savedLabels, accountLabels, activeLabels, onUpdateLabels } =
  useConversationLabels();
// Enquanto as etiquetas da conversa carregam, a lista não aparece: um toque ali
// gravaria só a nova e apagaria as que a conversa já tem (como no LabelBox).
const carregando = computed(() => Boolean(flags.value?.isFetching));

// As que a conversa já tem vêm primeiro, mas só na hora de abrir: depois a ordem
// fica parada, para a etiqueta não pular de lugar debaixo do dedo.
const primeirasAoAbrir = ref([]);
const etiquetasEmOrdem = computed(() =>
  accountLabels.value.toSorted(
    (a, b) =>
      Number(primeirasAoAbrir.value.includes(b.title)) -
      Number(primeirasAoAbrir.value.includes(a.title))
  )
);

// Toques seguidos: cada um parte do que já foi tocado (não do que o servidor
// devolveu), e as gravações vão uma de cada vez, na ordem dos toques.
const pendentes = ref(null);
const marcadas = computed(() => pendentes.value ?? savedLabels.value);
let fila = Promise.resolve();
let emVoo = 0;

const gravar = async titulos => {
  await onUpdateLabels(titulos);
  if (store.getters['conversationLabels/getUIFlags']?.isError)
    useAlert(t('PAINEL_DO_CONTATO.ETIQUETAS.ERRO'));
};
const salvar = titulos => {
  pendentes.value = titulos;
  emVoo += 1;
  fila = fila
    .then(() => gravar(titulos))
    .finally(() => {
      emVoo -= 1;
      // A última gravação respondeu: vale o que o servidor guardou.
      if (emVoo === 0) pendentes.value = null;
    });
  return fila;
};
const titulosAtuais = () =>
  pendentes.value ?? activeLabels.value.map(label => label.title);
const por = label => salvar([...titulosAtuais(), label.title]);
const tirar = titulo => salvar(titulosAtuais().filter(item => item !== titulo));

const abrir = () => {
  primeirasAoAbrir.value = [...savedLabels.value];
  dialogo.value?.open();
};
const fechar = () => dialogo.value?.close();

// "Criar etiqueta" abre fora da escolha: dentro do <dialog> a janela de criar
// ficaria presa à largura dele. Ao terminar, a escolha volta com a etiqueta nova.
const criando = ref(false);
const criar = () => {
  fechar();
  criando.value = true;
};
const terminouDeCriar = () => {
  criando.value = false;
  abrir();
};

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
      v-if="carregando"
      class="flex justify-center w-full py-6"
      data-test-id="etiquetas-carregando"
    >
      <Spinner />
    </div>
    <!-- A lista do painel antigo, sem o cabeçalho dela ("Adicionar etiquetas" e o
    atalho L, que só vale lá) e com alvos de 44 px. -->
    <div
      v-else
      class="w-full [&>div]:!max-h-80 [&>div>div:first-child]:!hidden [&_.search-input]:!min-h-11 [&_li_button]:!min-h-11"
    >
      <LabelDropdown
        :account-labels="etiquetasEmOrdem"
        :selected-labels="marcadas"
        @add="por"
        @remove="tirar"
      />
    </div>
    <template #footer>
      <div class="flex flex-wrap items-center justify-end gap-2">
        <Button
          v-if="podeCriar"
          type="button"
          slate
          ghost
          icon="i-lucide-plus"
          :label="t('PAINEL_DO_CONTATO.ETIQUETAS.CRIAR')"
          class="!min-h-11 me-auto"
          data-test-id="criar-etiqueta"
          @click="criar"
        />
        <Button
          type="button"
          :label="t('PAINEL_DO_CONTATO.ETIQUETAS.PRONTO')"
          class="!min-h-11"
          @click="fechar"
        />
      </div>
    </template>
  </Dialog>
  <Teleport to="body">
    <woot-modal v-if="criando" show @close="terminouDeCriar">
      <AddLabelModal @close="terminouDeCriar" />
    </woot-modal>
  </Teleport>
</template>
