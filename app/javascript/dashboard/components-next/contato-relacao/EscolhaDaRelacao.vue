<script setup>
// #2084/#2085 — a escolha "Este contato é", a frase do que ela faz e a pergunta de
// arquivar o card aberto. Usada no painel da conversa e na página do contato.
// Interessado (padrão) segue o funil; Parceiro do mercado e Não é negócio não viram card
// sozinhos e ficam fora dos Números. Card à mão continua possível. Muda quem a tela deixa
// (podeEditar) e o servidor também (dados.podeEditar, editar o contato).
//
// Sem acesso (401/403) ou com a chave desligada no servidor (404), a parte some: o
// pai esconde o título pelo evento `estado`.
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import EsqueletoOuErro from 'dashboard/components-next/painel-do-contato/EsqueletoOuErro.vue';
import {
  ESTADO,
  useParteDoPainel,
} from 'dashboard/components-next/painel-do-contato/useParteDoPainel';
import {
  RELACAO,
  RELACOES,
  chaveDoTexto,
  foraDoFunil,
  gravar,
  ler,
} from './relacaoDoContato';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
  podeEditar: { type: Boolean, default: false },
});

const emit = defineEmits(['estado']);

const { t } = useI18n();
const idDoEfeito = useId();

const rotulo = relacao => t(chaveDoTexto(relacao, 'ROTULO'));

const opcoes = computed(() =>
  RELACOES.map(relacao => ({
    value: relacao,
    label: rotulo(relacao),
    hint: t(chaveDoTexto(relacao, 'DICA')),
  }))
);

const SOME = [401, 403, 404];
const buscar = async contactId => {
  try {
    return await ler(contactId);
  } catch (erro) {
    if (!SOME.includes(erro?.response?.status)) throw erro;
    throw Object.assign(new Error('sem acesso'), { response: { status: 403 } });
  }
};

const { estado, dados, carregar } = useParteDoPainel(buscar, () => true);
watch(estado, novo => emit('estado', novo), { immediate: true });

const escolhida = ref(RELACAO.INTERESSADO);
watch(dados, novos => {
  if (novos) escolhida.value = novos.relacao;
});

const editavel = computed(
  () => props.podeEditar && Boolean(dados.value?.podeEditar)
);

const efeito = computed(() =>
  foraDoFunil(dados.value?.relacao)
    ? t('PAINEL_DO_CONTATO.RELACAO.EFEITO.FORA')
    : t('PAINEL_DO_CONTATO.RELACAO.EFEITO.INTERESSADO')
);

const aviso = (relacao, { cardsArquivados, cardsNaoArquivados }) =>
  [
    t('PAINEL_DO_CONTATO.RELACAO.SALVO', { relacao: rotulo(relacao) }),
    cardsArquivados &&
      t(
        'PAINEL_DO_CONTATO.RELACAO.ARQUIVADOS',
        { count: cardsArquivados },
        cardsArquivados
      ),
    cardsNaoArquivados &&
      t(
        'PAINEL_DO_CONTATO.RELACAO.NAO_ARQUIVADOS',
        { count: cardsNaoArquivados },
        cardsNaoArquivados
      ),
  ]
    .filter(Boolean)
    .join(' ');

// O contato é o da escolha: se a tela trocar de contato no meio, o aviso e a
// releitura não valem para o outro.
const salvando = ref(false);
const salvar = async (contactId, relacao, arquivarCards) => {
  salvando.value = true;
  try {
    const resposta = await gravar(contactId, relacao, { arquivarCards });
    if (contactId !== props.contactId) return;
    await carregar(contactId);
    useAlert(aviso(relacao, resposta));
  } catch {
    if (contactId !== props.contactId) return;
    escolhida.value = dados.value?.relacao || RELACAO.INTERESSADO;
    useAlert(t('PAINEL_DO_CONTATO.RELACAO.ERRO'));
  } finally {
    salvando.value = false;
  }
};

// Ao tirar do funil um contato Interessado com card aberto, pergunta antes:
// arquivar ou deixar. Entre Parceiro e Não é negócio não pergunta de novo.
const pergunta = ref(null);
const cardsAbertos = computed(() => dados.value?.cardsAbertos || 0);
// O contato e a relação da pergunta aberta; null: nada esperando resposta.
const pendente = ref(null);

const aoEscolher = () => {
  const relacao = escolhida.value;
  const saiDoFunil = !foraDoFunil(dados.value?.relacao) && foraDoFunil(relacao);
  if (saiDoFunil && cardsAbertos.value > 0) {
    pendente.value = { contactId: props.contactId, relacao };
    pergunta.value?.open();
    return;
  }
  salvar(props.contactId, relacao, false);
};

const responder = arquivarCards => {
  const resposta = pendente.value;
  if (!resposta) return;
  pendente.value = null;
  salvar(resposta.contactId, resposta.relacao, arquivarCards);
};
const arquivar = () => {
  responder(true);
  pergunta.value?.close();
};
// "Deixar", Esc ou tocar fora: muda a escolha e o card continua aberto.
const deixar = () => responder(false);

watch(
  () => props.contactId,
  contactId => {
    // Trocou de contato com a pergunta aberta: ela some sem gravar nada.
    if (pendente.value) {
      pendente.value = null;
      pergunta.value?.close();
    }
    carregar(contactId);
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-2" data-test-id="escolha-da-relacao">
    <EsqueletoOuErro
      v-if="!dados && estado !== ESTADO.PRONTO"
      :estado="estado"
      :linhas="1"
      @tentar="carregar(contactId)"
    />
    <template v-else-if="dados">
      <ChoiceSelect
        v-if="editavel"
        v-model="escolhida"
        :options="opcoes"
        :aria-label="t('PAINEL_DO_CONTATO.RELACAO.TITULO')"
        :aria-describedby="idDoEfeito"
        :disabled="salvando"
        @change="aoEscolher"
      />
      <p v-else class="m-0 text-sm font-medium text-n-slate-12">
        {{ rotulo(dados.relacao) }}
      </p>
      <p
        :id="idDoEfeito"
        class="m-0 text-sm text-n-slate-11"
        data-test-id="efeito-da-relacao"
      >
        {{ efeito }}
      </p>
    </template>
    <Dialog
      ref="pergunta"
      type="edit"
      :title="
        t(
          'PAINEL_DO_CONTATO.RELACAO.ARQUIVAR.TITULO',
          { count: cardsAbertos },
          cardsAbertos
        )
      "
      :description="t('PAINEL_DO_CONTATO.RELACAO.ARQUIVAR.TEXTO')"
      :confirm-button-label="t('PAINEL_DO_CONTATO.RELACAO.ARQUIVAR.SIM')"
      :cancel-button-label="t('PAINEL_DO_CONTATO.RELACAO.ARQUIVAR.NAO')"
      @confirm="arquivar"
      @close="deixar"
    />
  </div>
</template>
