<script setup>
// #2084/#2085 — a escolha "Este contato é", a frase do que ela faz e a pergunta de
// arquivar o card aberto. Usada no painel da conversa e na página do contato.
// Interessado (padrão) segue o funil; Parceiro do mercado e Não é negócio não viram card
// sozinhos e ficam fora dos Números. Card à mão continua possível. Muda quem a tela deixa
// (podeEditar) e o servidor também (dados.podeEditar, editar o contato).
import { computed, ref, watch } from 'vue';
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

const { t } = useI18n();

const rotulo = relacao => t(chaveDoTexto(relacao, 'ROTULO'));

const opcoes = computed(() =>
  RELACOES.map(relacao => ({
    value: relacao,
    label: rotulo(relacao),
    hint: t(chaveDoTexto(relacao, 'DICA')),
  }))
);

const { estado, dados, carregar } = useParteDoPainel(
  () => ler(props.contactId),
  () => true
);
watch(() => props.contactId, carregar, { immediate: true });

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

const salvando = ref(false);
const salvar = async (relacao, arquivarCards) => {
  salvando.value = true;
  try {
    const { cardsArquivados } = await gravar(props.contactId, relacao, {
      arquivarCards,
    });
    await carregar();
    const frase = t('PAINEL_DO_CONTATO.RELACAO.SALVO', {
      relacao: rotulo(relacao),
    });
    useAlert(
      cardsArquivados
        ? `${frase} ${t('PAINEL_DO_CONTATO.RELACAO.ARQUIVADOS', { count: cardsArquivados }, cardsArquivados)}`
        : frase
    );
  } catch {
    escolhida.value = dados.value?.relacao || RELACAO.INTERESSADO;
    useAlert(t('PAINEL_DO_CONTATO.RELACAO.ERRO'));
  } finally {
    salvando.value = false;
  }
};

// Ao tirar do funil um contato com card aberto, pergunta antes: arquivar ou deixar.
const pergunta = ref(null);
const cardsAbertos = computed(() => dados.value?.cardsAbertos || 0);
let respondida = false;

const aoEscolher = () => {
  const relacao = escolhida.value;
  if (foraDoFunil(relacao) && cardsAbertos.value > 0) {
    respondida = false;
    pergunta.value?.open();
    return;
  }
  salvar(relacao, false);
};
const arquivar = () => {
  respondida = true;
  pergunta.value?.close();
  salvar(escolhida.value, true);
};
// "Deixar", Esc ou tocar fora: muda a escolha e o card continua aberto.
const deixar = () => {
  if (respondida) return;
  respondida = true;
  salvar(escolhida.value, false);
};
</script>

<template>
  <div class="flex flex-col gap-2" data-test-id="escolha-da-relacao">
    <EsqueletoOuErro
      v-if="estado !== ESTADO.PRONTO"
      :estado="estado"
      :linhas="1"
      @tentar="carregar"
    />
    <template v-else>
      <ChoiceSelect
        v-if="editavel"
        v-model="escolhida"
        :options="opcoes"
        :aria-label="t('PAINEL_DO_CONTATO.RELACAO.TITULO')"
        :disabled="salvando"
        @change="aoEscolher"
      />
      <p v-else class="m-0 text-sm font-medium text-n-slate-12">
        {{ rotulo(dados.relacao) }}
      </p>
      <p class="m-0 text-sm text-n-slate-11" data-test-id="efeito-da-relacao">
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
