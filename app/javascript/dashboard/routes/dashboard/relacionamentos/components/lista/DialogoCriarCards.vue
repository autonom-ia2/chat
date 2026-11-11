<script setup>
import { computed, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import ResultadoDaAcao from './ResultadoDaAcao.vue';
import {
  rotuloDeCancelar,
  rotuloDeConfirmar,
  useEnvioEmFatias,
} from '../../lista/useEnvioEmFatias';

// #2894 — "Em qual funil?" e "Em qual etapa?" (o primeiro de cada já vem
// escolhido) e "Criar 12 cards". Enquanto cria: "50 de 120". Depois: "12 cards
// criados." e, se alguém ficou de fora, a lista com o motivo. Se parou no meio,
// diz quantas ainda não foram e oferece tentar de novo só com elas. Fechar o
// diálogo depois de criar avisa (`concluido`, com quem ainda falta) para a tela
// recarregar e desmarcar. Sem nenhum funil que a pessoa veja, não há campo nem
// escrita: uma frase e "Abrir o CRM" (`abrirCrm`).
const props = defineProps({
  pessoas: { type: Array, required: true },
  acoes: { type: Object, required: true },
});
const emit = defineEmits(['concluido', 'abrirCrm']);

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const idDoFunil = useId();
const idDaEtapa = useId();

const funis = ref([]);
const funilId = ref('');
const etapaId = ref('');
const {
  enviando,
  andamento,
  resultado,
  terminou,
  enviarOQueFalta,
  fechar,
  recomecar,
} = useEnvioEmFatias({
  contagem: 'criados',
  mensagemDeErro: () => t('RELACIONAMENTOS.LISTA.CARDS.ERRO'),
  aoConcluir: faltam => emit('concluido', faltam),
});

const semFunil = computed(() => funis.value.length === 0);
const opcoesDeFunil = computed(() =>
  funis.value.map(({ id, nome }) => ({ value: id, label: nome }))
);
const opcoesDeEtapa = computed(() =>
  (funis.value.find(funil => funil.id === funilId.value)?.etapas ?? []).map(
    ({ id, nome }) => ({ value: id, label: nome })
  )
);

const escolherFunil = id => {
  funilId.value = id;
  etapaId.value = opcoesDeEtapa.value[0]?.value ?? '';
};

const abrir = async () => {
  recomecar();
  try {
    funis.value = await props.acoes.funis();
  } catch {
    useAlert(t('RELACIONAMENTOS.COMUM.ERRO_GENERICO'));
    return;
  }
  escolherFunil(funis.value[0]?.id ?? '');
  dialogo.value?.open();
};

const criar = lote =>
  props.acoes.criarCards({
    ...lote,
    funilId: funilId.value,
    etapaId: etapaId.value,
  });

const irAoCrm = () => {
  dialogo.value?.close();
  emit('abrirCrm');
};

const aoConfirmar = () => {
  if (semFunil.value) return irAoCrm();
  if (terminou.value) return dialogo.value?.close();
  return enviarOQueFalta(props.pessoas, criar);
};

const rotuloDoBotao = computed(() => {
  if (semFunil.value) return t('RELACIONAMENTOS.LISTA.CARDS.ABRIR_CRM');
  const count = props.pessoas.length;
  return rotuloDeConfirmar(
    t,
    resultado.value,
    t('RELACIONAMENTOS.LISTA.CARDS.CRIAR', { count }, count)
  );
});
const rotuloDeSair = computed(() =>
  semFunil.value
    ? t('RELACIONAMENTOS.COMUM.FECHAR')
    : rotuloDeCancelar(t, resultado.value)
);

const criados = count =>
  t('RELACIONAMENTOS.LISTA.CARDS.CRIADOS', { count }, count);

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    type="edit"
    width="md"
    :confirm-button-label="rotuloDoBotao"
    :cancel-button-label="rotuloDeSair"
    :show-cancel-button="!terminou"
    :is-loading="enviando"
    :close-on-outside-click="!resultado"
    @confirm="aoConfirmar"
    @close="fechar"
  >
    <TituloDoDialogo :titulo="t('RELACIONAMENTOS.LISTA.CARDS.TITULO')" />
    <div data-relacionamentos="dialogo-cards">
      <ResultadoDaAcao
        :andamento="andamento"
        :resultado="resultado"
        :frase="criados"
      />
      <p
        v-if="semFunil"
        data-relacionamentos="sem-funil"
        class="m-0 text-base text-n-slate-12"
      >
        {{ t('RELACIONAMENTOS.LISTA.CARDS.SEM_FUNIL') }}
      </p>
      <div v-else-if="!resultado" class="flex flex-col gap-5">
        <div class="flex flex-col gap-2">
          <label :for="idDoFunil" class="text-sm font-medium text-n-slate-12">
            {{ t('RELACIONAMENTOS.LISTA.CARDS.FUNIL') }}
          </label>
          <ChoiceSelect
            :model-value="funilId"
            :options="opcoesDeFunil"
            :trigger-id="idDoFunil"
            :aria-label="t('RELACIONAMENTOS.LISTA.CARDS.FUNIL')"
            @update:model-value="escolherFunil"
          />
        </div>
        <div class="flex flex-col gap-2">
          <label :for="idDaEtapa" class="text-sm font-medium text-n-slate-12">
            {{ t('RELACIONAMENTOS.LISTA.CARDS.ETAPA') }}
          </label>
          <ChoiceSelect
            v-model="etapaId"
            :options="opcoesDeEtapa"
            :trigger-id="idDaEtapa"
            :aria-label="t('RELACIONAMENTOS.LISTA.CARDS.ETAPA')"
          />
        </div>
      </div>
    </div>
  </Dialog>
</template>
