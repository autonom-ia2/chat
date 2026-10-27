<script setup>
// #2202 (PR 3) — "Etiquetas desta conversa": a escolha de etiquetas da conversa
// aberta, pelo ⋯ do topo e pelo bloco "Etiquetas" do painel. A lista é a mesma
// do painel antigo (LabelDropdown), com a mesma action (conversationLabels/update):
// tocar numa etiqueta põe ou tira na hora.
import { computed, nextTick, ref, shallowRef, watch } from 'vue';
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
const lista = ref(null);
const eu = useMapGetter('getCurrentUser');
const contaId = useMapGetter('getCurrentAccountId');
const flags = useMapGetter('conversationLabels/getUIFlags');
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

// Cada toque vira uma intenção — pôr ou tirar uma etiqueta — presa à conversa em
// que a pessoa tocou. As gravações saem uma de cada vez, na ordem dos toques, e
// cada uma aplica a intenção sobre o que aquela conversa tem no store na hora em
// que sai. Assim a etiqueta não vai para outra conversa, a mudança que outra
// pessoa fez nesse meio-tempo não se perde e, depois de um erro, a próxima parte
// do que está gravado.
const aplicar = (titulos, { acao, titulo }) => {
  if (acao === 'tirar') return titulos.filter(item => item !== titulo);
  return titulos.includes(titulo) ? titulos : [...titulos, titulo];
};
const gravadasEm = id =>
  store.getters['conversationLabels/getConversationLabels'](id);

// Na tela: o que está gravado, com as intenções desta conversa que ainda não
// voltaram do servidor por cima (a marca aparece na hora do toque).
const pendentes = shallowRef([]);
const marcadas = computed(() =>
  pendentes.value
    .filter(intencao => intencao.conversaId === conversaId.value)
    .reduce(aplicar, savedLabels.value)
);

let fila = Promise.resolve();
let ultimaIntencao = 0;
const gravar = async intencao => {
  await store.dispatch('conversationLabels/update', {
    conversationId: intencao.conversaId,
    labels: aplicar(gravadasEm(intencao.conversaId), intencao),
  });
  // A action não rejeita: o erro do servidor chega pela flag.
  if (store.getters['conversationLabels/getUIFlags']?.isError)
    throw new Error('etiquetas da conversa não gravadas');
};
const tocar = (acao, titulo) => {
  ultimaIntencao += 1;
  const intencao = {
    id: ultimaIntencao,
    acao,
    titulo,
    conversaId: conversaId.value,
  };
  pendentes.value = [...pendentes.value, intencao];
  fila = fila
    .then(() => gravar(intencao))
    .catch(() => useAlert(t('PAINEL_DO_CONTATO.ETIQUETAS.ERRO')))
    .finally(() => {
      // Respondeu (ou falhou): na tela passa a valer o que está gravado.
      pendentes.value = pendentes.value.filter(item => item.id !== intencao.id);
    });
  return fila;
};
const por = label => tocar('por', label.title);
const tirar = titulo => tocar('tirar', titulo);

// Enter na busca não pode virar o envio do <form> do Dialog: o navegador
// "clicaria" o primeiro botão da lista e poria ou tiraria a primeira etiqueta.
// Nos botões da lista o Enter continua valendo (é o toque pelo teclado).
const segurarEnterDaBusca = evento => {
  if (evento.target instanceof HTMLInputElement) evento.preventDefault();
};

// Ao fechar, o foco volta para quem abriu (o ⋯ do topo ou o bloco do painel).
const aberta = ref(false);
let devolverFoco = null;
const abrir = paraOndeVoltar => {
  if (paraOndeVoltar) devolverFoco = paraOndeVoltar;
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
  if (criando.value) return;
  nextTick(() => devolverFoco?.());
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

// Trocar de conversa (Alt+J/K, a lista) fecha a escolha e larga as marcas que
// ainda não voltaram; o que já está na fila continua indo para a conversa certa.
watch(conversaId, () => {
  pendentes.value = [];
  if (aberta.value) fechar();
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
      data-test-id="etiquetas-carregando"
    >
      <Spinner />
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
