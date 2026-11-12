<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CartoesDeEscolha from './CartoesDeEscolha.vue';

// #2894 — UMA pergunta por tela, só quando a leitura pede. Cada pergunta tem
// Continuar (sempre ligado: sem resposta, o clique diz o que falta) e Voltar.
const props = defineProps({
  pergunta: { type: Object, required: true },
  respostas: { type: Object, required: true },
  colunas: { type: Array, default: () => [] },
  podeContinuar: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
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

const CLIENTES = 'clientes';
const RESPOSTA_ALGUMAS = 'algumas';

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

const ehDeClientes = computed(() => props.pergunta.id === CLIENTES);
const titulo = computed(() =>
  ehDeClientes.value
    ? t('RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.TITULO')
    : t('RELACIONAMENTOS_TRAZER.PERGUNTAS.TELEFONE.TITULO', {
        coluna: props.pergunta.coluna,
      })
);
const opcoes = computed(() =>
  opcoesDa[props.pergunta.id].map(([opcaoId, chave]) => ({
    id: opcaoId,
    rotulo: t(chave),
  }))
);
const respostaAtual = computed(() => props.respostas[props.pergunta.id] || '');
const pedeColuna = computed(
  () => ehDeClientes.value && respostaAtual.value === RESPOSTA_ALGUMAS
);
const opcoesDeColuna = computed(() =>
  props.colunas.map(coluna => ({ value: coluna.nome, label: coluna.nome }))
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
      class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
    >
      {{ titulo }}
    </h1>
    <CartoesDeEscolha
      :opcoes="opcoes"
      :model-value="respostaAtual"
      :rotulo-id="`${id}-titulo`"
      :invalido="Boolean(erro) && !respostaAtual"
      :descrito-por="erro ? `${id}-erro` : undefined"
      @update:model-value="emit('responder', pergunta.id, $event)"
    />
    <div v-if="pedeColuna" class="flex flex-col gap-2 max-w-sm">
      <label :for="`${id}-coluna`" class="text-base text-n-slate-12">
        {{ t('RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.QUAL_COLUNA') }}
      </label>
      <ChoiceSelect
        :trigger-id="`${id}-coluna`"
        :model-value="respostas.colunaCliente || ''"
        :options="opcoesDeColuna"
        :aria-label="t('RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.QUAL_COLUNA')"
        :invalid="Boolean(erro) && Boolean(respostaAtual)"
        :described-by="erro ? `${id}-erro` : undefined"
        @update:model-value="emit('escolherColuna', $event)"
      />
    </div>
    <p
      v-if="erro"
      :id="`${id}-erro`"
      data-relacionamentos="erro-da-pergunta"
      role="alert"
      class="m-0 text-base font-medium text-n-ruby-11"
    >
      {{ erro }}
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
        @click="emit('voltar')"
      />
    </div>
  </section>
</template>
