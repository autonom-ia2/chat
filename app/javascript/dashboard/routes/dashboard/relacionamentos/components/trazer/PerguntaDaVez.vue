<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CartoesDeEscolha from './CartoesDeEscolha.vue';
import { chaveDaColuna, podeDizerQuemEhCliente } from '../../trazer/destinos';
import { PERGUNTA_CLIENTES, RESPOSTA_ALGUMAS } from '../../trazer/respostas';

// #2894 — UMA pergunta por tela, só quando a leitura pede. Cada pergunta tem
// Continuar (sempre ligado: sem resposta, o clique diz o que falta) e Voltar.
// #2896 — a coluna que diz quem é cliente vai pela chave dela (o índice, quando
// vem do servidor; 0 é a primeira). Coluna sem título aparece pela posição. Só
// entram as colunas que podem dizer isso; sem nenhuma, "Algumas" não aparece.
// `temEmpresa`: sem empresa na leitura, a pergunta do telefone não oferece "Da
// empresa".
// Fatia 2 — `deNovo`: a pessoa mudou a coluna de que esta resposta dependia e a
// pergunta diz por que está sendo feita de novo. `recusa` (`{ chave }`): a
// resposta que o servidor não aceitou (ou que falhou) fica dita aqui, como
// alerta, com o foco de volta nas respostas. `relendo`: a planilha está sendo
// lida de novo. Com a resposta sendo gravada, o Voltar fica desligado.
const props = defineProps({
  pergunta: { type: Object, required: true },
  respostas: { type: Object, required: true },
  colunas: { type: Array, default: () => [] },
  temEmpresa: { type: Boolean, default: true },
  podeContinuar: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
  relendo: { type: Boolean, default: false },
  deNovo: { type: Boolean, default: false },
  recusa: { type: Object, default: null },
});
const emit = defineEmits([
  'responder',
  'escolherColuna',
  'continuar',
  'voltar',
]);

const { t } = useI18n();
const id = useId();
const raiz = ref(null);
const erro = ref('');

const RESPOSTA_DA_EMPRESA = 'da_empresa';

const nomeDaColuna = (nome, indice) =>
  nome ||
  t('RELACIONAMENTOS_TRAZER.GUARDAR.COLUNA_SEM_NOME', {
    numero: (indice ?? 0) + 1,
  });

const opcoesDa = {
  clientes: [
    ['sim_todas', 'RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.SIM_TODAS'],
    ['ainda_nao', 'RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.AINDA_NAO'],
    ['algumas', 'RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.ALGUMAS'],
  ],
  telefone: [
    ['da_pessoa', 'RELACIONAMENTOS_TRAZER.PERGUNTAS.TELEFONE.DA_PESSOA'],
    ['da_empresa', 'RELACIONAMENTOS_TRAZER.PERGUNTAS.TELEFONE.DA_EMPRESA'],
    ['nao_usar', 'RELACIONAMENTOS_TRAZER.PERGUNTAS.TELEFONE.NAO_USAR'],
  ],
};

const ehDeClientes = computed(() => props.pergunta.id === PERGUNTA_CLIENTES);
const porQueDeNovo = computed(() =>
  ehDeClientes.value
    ? t('RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.DE_NOVO')
    : t('RELACIONAMENTOS_TRAZER.PERGUNTAS.TELEFONE.DE_NOVO')
);
const titulo = computed(() =>
  ehDeClientes.value
    ? t('RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.TITULO')
    : t('RELACIONAMENTOS_TRAZER.PERGUNTAS.TELEFONE.TITULO', {
        coluna: nomeDaColuna(props.pergunta.coluna, props.pergunta.indice),
      })
);
const opcoesDeColuna = computed(() =>
  props.colunas.filter(podeDizerQuemEhCliente).map(coluna => ({
    value: chaveDaColuna(coluna),
    label: nomeDaColuna(coluna.nome, coluna.indice),
  }))
);
// A resposta que a leitura não comporta não é oferecida.
const cabe = opcaoId => {
  if (opcaoId === RESPOSTA_ALGUMAS) return opcoesDeColuna.value.length > 0;
  if (opcaoId === RESPOSTA_DA_EMPRESA) return props.temEmpresa;
  return true;
};
const opcoes = computed(() =>
  opcoesDa[props.pergunta.id]
    .filter(([opcaoId]) => cabe(opcaoId))
    .map(([opcaoId, chave]) => ({ id: opcaoId, rotulo: t(chave) }))
);
const respostaAtual = computed(() => props.respostas[props.pergunta.id] || '');
const pedeColuna = computed(
  () => ehDeClientes.value && respostaAtual.value === RESPOSTA_ALGUMAS
);

// Nada de botão desligado por falta de preenchimento: o clique diz o que falta
// e leva o foco até lá.
const tentarContinuar = () => {
  if (props.podeContinuar) {
    erro.value = '';
    emit('continuar');
    return;
  }
  if (!respostaAtual.value) {
    erro.value = t('RELACIONAMENTOS_TRAZER.PERGUNTAS.ERRO_ESCOLHA');
    raiz.value?.querySelector('[data-relacionamentos="resposta"]')?.focus();
    return;
  }
  erro.value = t('RELACIONAMENTOS_TRAZER.PERGUNTAS.ERRO_COLUNA');
  document.getElementById(`${id}-coluna`)?.focus();
};

watch([respostaAtual, () => props.respostas.colunaCliente], () => {
  erro.value = '';
});

// O que o alerta diz: o que falta preencher ou, sem isso, a recusa do servidor.
const mensagem = computed(() => {
  if (erro.value) return erro.value;
  return props.recusa ? t(props.recusa.chave) : '';
});

// A recusa chegou: o foco volta à resposta escolhida (ou à primeira).
const focarAResposta = async () => {
  await nextTick();
  const respostasDaTela = raiz.value?.querySelectorAll(
    '[data-relacionamentos="resposta"]'
  );
  const escolhida = [...(respostasDaTela ?? [])].find(
    resposta => resposta.getAttribute('data-resposta') === respostaAtual.value
  );
  (escolhida ?? respostasDaTela?.[0])?.focus();
};
watch(
  () => props.recusa,
  recusa => {
    if (recusa) focarAResposta();
  }
);
</script>

<template>
  <section
    ref="raiz"
    data-relacionamentos="pergunta"
    :data-pergunta="pergunta.id"
    class="flex flex-col gap-8"
  >
    <h1
      :id="`${id}-titulo`"
      data-titulo-da-tela
      tabindex="-1"
      :aria-describedby="deNovo ? `${id}-de-novo` : undefined"
      class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
    >
      {{ titulo }}
    </h1>
    <p
      v-if="deNovo"
      :id="`${id}-de-novo`"
      data-relacionamentos="pergunta-de-novo"
      class="m-0 -mt-4 text-lg text-n-slate-11"
    >
      {{ porQueDeNovo }}
    </p>
    <CartoesDeEscolha
      :opcoes="opcoes"
      :model-value="respostaAtual"
      :rotulo-id="`${id}-titulo`"
      :invalido="Boolean(erro) && !respostaAtual"
      :descrito-por="mensagem ? `${id}-erro` : undefined"
      @update:model-value="emit('responder', pergunta.id, $event)"
    />
    <div v-if="pedeColuna" class="flex flex-col gap-2 max-w-sm">
      <label :for="`${id}-coluna`" class="text-base text-n-slate-12">
        {{ t('RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.QUAL_COLUNA') }}
      </label>
      <ChoiceSelect
        :trigger-id="`${id}-coluna`"
        :model-value="respostas.colunaCliente ?? ''"
        :options="opcoesDeColuna"
        :aria-label="t('RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.QUAL_COLUNA')"
        :invalid="Boolean(erro) && Boolean(respostaAtual)"
        :described-by="erro ? `${id}-erro` : undefined"
        @update:model-value="emit('escolherColuna', $event)"
      />
    </div>
    <p
      v-if="mensagem"
      :id="`${id}-erro`"
      data-relacionamentos="erro-da-pergunta"
      role="alert"
      class="m-0 text-base font-medium text-n-ruby-11"
    >
      {{ mensagem }}
    </p>
    <div class="flex flex-wrap items-center gap-3">
      <Button
        data-relacionamentos="continuar"
        :label="t('RELACIONAMENTOS.COMUM.CONTINUAR')"
        size="lg"
        :disabled="ocupado"
        :is-loading="ocupado"
        @click="tentarContinuar"
      />
      <Button
        slate
        faded
        size="lg"
        :label="t('RELACIONAMENTOS.COMUM.VOLTAR')"
        :disabled="ocupado"
        @click="emit('voltar')"
      />
      <p
        data-relacionamentos="relendo"
        role="status"
        class="m-0 text-base text-n-slate-11"
      >
        {{ relendo ? t('RELACIONAMENTOS_TRAZER.CONFERIR.RELENDO') : '' }}
      </p>
    </div>
  </section>
</template>
