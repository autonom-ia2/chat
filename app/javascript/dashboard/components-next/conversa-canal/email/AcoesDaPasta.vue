<script setup>
// Spam e Lixeira no topo da conversa de e-mail (#1809, fase 1), como os botões do
// Gmail em cima do assunto. Na Entrada: "Spam" e "Lixeira". No Spam: "Não é spam". Na
// Lixeira: "Restaurar" e "Excluir para sempre" (com confirmação; quem tem acesso à caixa
// pode, decisão do Rodrigo 18/10). Fora da Lixeira nada é apagado, e nada muda na conta
// de e-mail do cliente; depois da ação, a tela volta para a lista em que a pessoa estava.
import { computed, ref, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Icon from 'next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useAlert } from 'dashboard/composables';
import PastasDoEmailAPI from 'dashboard/api/pastasDoEmail';
import { PASTAS, usePastaDoEmail } from './pastaDoEmail';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const {
  pasta: pastaDaLista,
  abrirPasta,
  moverConversa,
  excluirConversa,
} = usePastaDoEmail();
const confirmar = useTemplateRef('confirmar');

// De qual lista a conversa foi aberta, para voltar para ela depois de mover.
const LISTA_DA_ROTA = {
  inbox_conversation: 'home',
  conversations_through_label: 'label_conversations',
  conversations_through_team: 'team_conversations',
  conversations_through_folders: 'folder_conversations',
};
const voltarParaALista = async () => {
  if (route.params.inbox_id) {
    await abrirPasta(route.params.inbox_id, pastaDaLista.value);
    return;
  }
  const { conversation_id: _aberta, ...params } = route.params;
  await router.push({ name: LISTA_DA_ROTA[route.name] || 'home', params });
};

const conversaId = computed(() => route.params.conversation_id);
const pastaDaConversa = ref(null);
const movendo = ref(false);

watch(
  conversaId,
  async id => {
    pastaDaConversa.value = null;
    if (!id) return;
    try {
      const { data } = await PastasDoEmailAPI.ler(id);
      if (id === conversaId.value) pastaDaConversa.value = data.pasta;
    } catch {
      pastaDaConversa.value = null;
    }
  },
  { immediate: true }
);

const acoes = computed(() => {
  if (pastaDaConversa.value === PASTAS.SPAM) {
    return [
      {
        para: null,
        chave: 'NAO_E_SPAM',
        icone: 'i-lucide-inbox',
        aviso: 'VOLTOU',
      },
    ];
  }
  if (pastaDaConversa.value === PASTAS.LIXEIRA) {
    return [
      {
        para: null,
        chave: 'RESTAURAR',
        icone: 'i-lucide-undo-2',
        aviso: 'VOLTOU',
      },
    ];
  }
  return [
    {
      para: PASTAS.SPAM,
      chave: 'MARCAR_SPAM',
      icone: 'i-lucide-octagon-alert',
      aviso: 'FOI_PARA_SPAM',
    },
    {
      para: PASTAS.LIXEIRA,
      chave: 'MOVER_LIXEIRA',
      icone: 'i-lucide-trash-2',
      aviso: 'FOI_PARA_LIXEIRA',
    },
  ];
});

const excluir = async () => {
  confirmar.value?.close();
  movendo.value = true;
  try {
    await excluirConversa(conversaId.value);
    useAlert(t('CONVERSA_CANAL.EMAIL.PASTA.EXCLUIDA'));
    await voltarParaALista();
  } catch {
    useAlert(t('CONVERSA_CANAL.EMAIL.PASTA.FALHOU_EXCLUIR'));
  } finally {
    movendo.value = false;
  }
};

const mover = async acao => {
  if (movendo.value) return;
  movendo.value = true;
  try {
    await moverConversa(conversaId.value, acao.para);
    useAlert(t(`CONVERSA_CANAL.EMAIL.PASTA.${acao.aviso}`));
    await voltarParaALista();
  } catch {
    useAlert(t('CONVERSA_CANAL.EMAIL.PASTA.FALHOU'));
  } finally {
    movendo.value = false;
  }
};
</script>

<template>
  <div v-if="conversaId" class="flex items-center gap-1" data-acoes-da-pasta>
    <button
      v-for="acao in acoes"
      :key="acao.chave"
      type="button"
      class="inline-flex items-center gap-1.5 min-h-10 px-3 rounded-full text-sm text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :disabled="movendo"
      :title="t(`CONVERSA_CANAL.EMAIL.PASTA.${acao.chave}_DICA`)"
      :data-acao-da-pasta="acao.para || 'entrada'"
      @click="mover(acao)"
    >
      <Icon :icon="acao.icone" class="size-4" />
      <span class="max-sm:sr-only">
        {{ t(`CONVERSA_CANAL.EMAIL.PASTA.${acao.chave}`) }}
      </span>
    </button>
    <button
      v-if="pastaDaConversa === PASTAS.LIXEIRA"
      type="button"
      class="inline-flex items-center gap-1.5 min-h-10 px-3 rounded-full text-sm text-n-ruby-11 hover:bg-n-ruby-3 disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-ruby-9"
      :disabled="movendo"
      :title="t('CONVERSA_CANAL.EMAIL.PASTA.EXCLUIR_PARA_SEMPRE_DICA')"
      data-excluir-para-sempre
      @click="confirmar?.open()"
    >
      <Icon icon="i-lucide-trash" class="size-4" />
      <span class="max-sm:sr-only">
        {{ t('CONVERSA_CANAL.EMAIL.PASTA.EXCLUIR_PARA_SEMPRE') }}
      </span>
    </button>
    <Dialog
      ref="confirmar"
      type="alert"
      :title="t('CONVERSA_CANAL.EMAIL.PASTA.EXCLUIR_TITULO')"
      :description="t('CONVERSA_CANAL.EMAIL.PASTA.EXCLUIR_TEXTO')"
      :confirm-button-label="
        t('CONVERSA_CANAL.EMAIL.PASTA.EXCLUIR_PARA_SEMPRE')
      "
      :cancel-button-label="t('CONVERSA_CANAL.EMAIL.CANCELAR')"
      @confirm="excluir"
    />
  </div>
  <!-- Fora de uma conversa aberta: não mostra nada. -->
  <template v-else />
</template>
