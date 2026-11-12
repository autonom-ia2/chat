<script setup>
import { computed, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import { PONTO } from '../comum/ponto';
import { useEnvio } from '../../lista/useEnvio';

// #2894 — "Em qual funil?" e "Em qual etapa?" (o primeiro de cada já vem
// escolhido) e "Criar 12 cards". Depois: "12 cards criados." e, se alguém ficou
// de fora, a lista com o motivo. Fechar o diálogo depois de criar avisa
// (`concluido`) para a tela desmarcar a turma.
const props = defineProps({
  pessoas: { type: Array, required: true },
  acoes: { type: Object, required: true },
});
const emit = defineEmits(['concluido']);

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const idDoFunil = useId();
const idDaEtapa = useId();

const funis = ref([]);
const funilId = ref('');
const etapaId = ref('');
const resultado = ref(null);
const { enviando, enviar } = useEnvio(() =>
  t('RELACIONAMENTOS.LISTA.CARDS.ERRO')
);

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
  resultado.value = null;
  try {
    funis.value = await props.acoes.funis();
  } catch {
    useAlert(t('RELACIONAMENTOS.COMUM.ERRO_GENERICO'));
    return;
  }
  escolherFunil(funis.value[0]?.id ?? '');
  dialogo.value?.open();
};

const criar = async () => {
  const feito = await enviar(() =>
    props.acoes.criarCards({
      pessoas: props.pessoas,
      funilId: funilId.value,
      etapaId: etapaId.value,
    })
  );
  if (feito) resultado.value = feito;
};

const aoConfirmar = () => (resultado.value ? dialogo.value?.close() : criar());
const aoFechar = () => {
  if (resultado.value) emit('concluido');
};

const rotuloDoBotao = computed(() => {
  if (resultado.value) return t('RELACIONAMENTOS.LISTA.CARDS.PRONTO');
  const count = props.pessoas.length;
  return t('RELACIONAMENTOS.LISTA.CARDS.CRIAR', { count }, count);
});

const motivoEmPalavras = motivo =>
  t(`RELACIONAMENTOS.LISTA.CARDS.MOTIVO_${motivo.toUpperCase()}`);

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    type="edit"
    width="md"
    :confirm-button-label="rotuloDoBotao"
    :cancel-button-label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
    :show-cancel-button="!resultado"
    :is-loading="enviando"
    :close-on-outside-click="!resultado"
    @confirm="aoConfirmar"
    @close="aoFechar"
  >
    <TituloDoDialogo :titulo="t('RELACIONAMENTOS.LISTA.CARDS.TITULO')" />
    <div data-relacionamentos="dialogo-cards">
      <!-- Região viva permanente: já está aqui, vazia, quando o resultado chega. -->
      <div role="status" class="flex flex-col gap-3">
        <template v-if="resultado">
          <p class="m-0 text-base font-medium text-n-slate-12">
            {{
              t(
                'RELACIONAMENTOS.LISTA.CARDS.CRIADOS',
                { count: resultado.criados },
                resultado.criados
              )
            }}
          </p>
          <template v-if="resultado.deFora.length">
            <p class="m-0 text-sm text-n-slate-11">
              {{ t('RELACIONAMENTOS.LISTA.CARDS.FICARAM_DE_FORA') }}
            </p>
            <ul
              class="flex flex-col gap-1 p-0 m-0 text-sm list-none text-n-slate-12"
            >
              <li v-for="item in resultado.deFora" :key="item.id">
                {{ item.nome }} {{ PONTO }} {{ motivoEmPalavras(item.motivo) }}
              </li>
            </ul>
          </template>
        </template>
      </div>
      <div v-if="!resultado" class="flex flex-col gap-5">
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
