<script setup>
// #2202 (PR 3) — "Etiquetas desta conversa": a escolha de etiquetas da conversa
// aberta, pelo ⋯ do topo e pelo bloco do painel. A lista é a do painel antigo
// (LabelDropdown). Tocar numa etiqueta põe ou tira só ela, na hora: o servidor
// aplica a intenção sobre o que a conversa tem (useEtiquetasDaConversa), e as
// duas janelas mostram as mesmas marcas.
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
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
import { useEtiquetasDaConversa } from './useEtiquetasDaConversa';

const { t } = useI18n();
const dialogo = ref(null);
const lista = ref(null);
const eu = useMapGetter('getCurrentUser');
const contaId = useMapGetter('getCurrentAccountId');
const conversaAberta = useMapGetter('getSelectedChat');
const conversaId = computed(() => conversaAberta.value?.id);
// Como no painel antigo (LabelBox): criar etiqueta é de quem administra etiquetas.
const podeCriar = computed(() =>
  hasPermissions(
    ['administrator', 'label_manage'],
    getUserPermissions(eu.value, contaId.value)
  )
);
const { savedLabels, accountLabels } = useConversationLabels();
const { temRegistro, carregar, marcadasEm, tocar } = useEtiquetasDaConversa();
// Sem o registro das etiquetas desta conversa, a lista não aparece: mostraria
// como tiradas as que ela tem. Nada se grava até ele chegar. Se a busca falhar,
// a janela diz isso e oferece tentar de novo, em vez de carregar para sempre.
const falhouAoCarregar = ref(false);
const semRegistro = computed(() => !temRegistro(conversaId.value));
const carregando = computed(() => semRegistro.value && !falhouAoCarregar.value);
const buscarRegistro = async () => {
  const id = conversaId.value;
  falhouAoCarregar.value = false;
  const chegou = await carregar(id);
  if (!chegou && id === conversaId.value) falhouAoCarregar.value = true;
};

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
const marcadas = computed(() =>
  marcadasEm(conversaId.value, savedLabels.value)
);

// Cada toque leva a conversa do momento do toque. O aviso de erro sai do
// resultado desta chamada, não de uma flag que outra gravação pode ter mudado.
const mudar = async (acao, titulo) => {
  const id = conversaId.value;
  if (!temRegistro(id)) return;
  const gravou = await tocar(id, acao, titulo);
  if (!gravou) useAlert(t('PAINEL_DO_CONTATO.ETIQUETAS.ERRO'));
};
const por = label => mudar('por', label.title);
const tirar = titulo => mudar('tirar', titulo);

// Enter na busca não pode virar o envio do <form> do Dialog: o navegador
// "clicaria" o primeiro botão da lista e poria ou tiraria a primeira etiqueta.
// Nos botões da lista o Enter continua valendo (é o toque pelo teclado).
const segurarEnterDaBusca = evento => {
  if (evento.target instanceof HTMLInputElement) evento.preventDefault();
};

// Ao fechar, o foco volta para quem abriu (o ⋯ do topo ou o bloco do painel).
const aberta = ref(false);
let devolverFoco = null;
let fecharSemDevolver = false;
const abrir = paraOndeVoltar => {
  if (paraOndeVoltar) devolverFoco = paraOndeVoltar;
  if (semRegistro.value) buscarRegistro();
  primeirasAoAbrir.value = [...savedLabels.value];
  aberta.value = true;
  dialogo.value?.open();
};
const fechar = () => dialogo.value?.close();

// "Criar etiqueta" abre fora da escolha: dentro do <dialog> a janela de criar
// ficaria presa à largura dele. Ao terminar, a escolha volta com a etiqueta nova.
const criando = ref(false);
const textoParaCriar = ref('');
let conversaAoCriar = null;
const aoFechar = () => {
  aberta.value = false;
  const devolver = !fecharSemDevolver && !criando.value;
  fecharSemDevolver = false;
  if (devolver) nextTick(() => devolverFoco?.());
};
const criar = () => {
  // Como no LabelDropdown antigo: a janela de criar já vem com o que foi buscado.
  textoParaCriar.value = lista.value?.parsedSearch || '';
  conversaAoCriar = conversaId.value;
  criando.value = true;
  fechar();
};
const terminouDeCriar = () => {
  if (!criando.value) return;
  criando.value = false;
  if (conversaAoCriar === conversaId.value) {
    abrir();
    return;
  }
  nextTick(() => devolverFoco?.());
};

// Aberta sem o registro, a ordem é pega quando ele chega: senão as que a
// conversa tem não viriam primeiro.
watch(carregando, (agora, antes) => {
  if (aberta.value && antes && !agora && !semRegistro.value) {
    primeirasAoAbrir.value = [...savedLabels.value];
  }
});

// Trocar de conversa (Alt+J/K, a lista) fecha a escolha sem puxar o foco para
// trás. As marcas que ainda não voltaram continuam: são da conversa do toque, e
// a tela só as mostra nela.
watch(conversaId, () => {
  if (!aberta.value) return;
  fecharSemDevolver = true;
  fechar();
});

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    data-dialogo-etiquetas
    :title="t('PAINEL_DO_CONTATO.ETIQUETAS.DIALOGO_TITULO')"
    :description="t('PAINEL_DO_CONTATO.ETIQUETAS.DIALOGO_FRASE')"
    width="sm"
    @close="aoFechar"
  >
    <div
      v-if="carregando"
      class="flex justify-center w-full py-6"
      role="status"
      :aria-label="t('PAINEL_DO_CONTATO.CARREGANDO')"
      data-test-id="etiquetas-carregando"
    >
      <Spinner />
    </div>
    <div
      v-else-if="semRegistro"
      class="flex flex-col items-center w-full gap-3 py-6 text-center"
      role="alert"
      data-test-id="etiquetas-falhou"
    >
      <p class="m-0 text-sm text-n-slate-12">
        {{ t('PAINEL_DO_CONTATO.ETIQUETAS.ERRO_AO_CARREGAR') }}
      </p>
      <Button
        type="button"
        slate
        faded
        icon="i-lucide-rotate-cw"
        :label="t('PAINEL_DO_CONTATO.ETIQUETAS.TENTAR_DE_NOVO')"
        class="!min-h-11"
        data-test-id="etiquetas-tentar-de-novo"
        @click="buscarRegistro"
      />
    </div>
    <!-- A lista do painel antigo, sem o cabeçalho dela ("Adicionar etiquetas" e o
    atalho L, que só vale lá), com a caixa da busca do tamanho do campo e alvos
    de 44 px. -->
    <div
      v-else
      class="w-full [&>div]:!max-h-80 [&>div>div:first-child]:!hidden [&_div:has(>.search-input)]:!max-h-none [&_.search-input]:!min-h-11 [&_li_button]:!min-h-11"
      data-test-id="lista-de-etiquetas"
      @keydown.enter="segurarEnterDaBusca"
    >
      <LabelDropdown
        ref="lista"
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
          data-test-id="etiquetas-pronto"
          @click="fechar"
        />
      </div>
    </template>
  </Dialog>
  <Teleport to="body">
    <woot-modal v-if="criando" show @close="terminouDeCriar">
      <AddLabelModal :prefill-title="textoParaCriar" @close="terminouDeCriar" />
    </woot-modal>
  </Teleport>
</template>
