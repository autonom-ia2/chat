<script setup>
import { computed, ref, useId, useTemplateRef, watch } from 'vue';
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

// #2894 — diálogo pequeno: escolher uma etiqueta e colocar nas pessoas
// marcadas. Nada vem escolhido, e o botão está sempre ligado: sem escolha, o clique não
// fecha, diz o que falta e leva o foco ao campo. Enquanto coloca: "50 de 120".
// Deu tudo certo: avisa e fecha. Se alguém ficou de fora ou parou no meio, o
// diálogo fica aberto e diz quem, por quê e quantas ainda não foram.
const props = defineProps({
  pessoas: { type: Array, required: true },
  acoes: { type: Object, required: true },
});
const emit = defineEmits(['concluido']);

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const campo = useTemplateRef('campo');
const idDoCampo = useId();
const idDoAviso = useId();

const etiquetas = ref([]);
const escolhida = ref('');
const faltaEscolher = ref(false);
watch(escolhida, () => {
  faltaEscolher.value = false;
});
const {
  enviando,
  andamento,
  resultado,
  terminou,
  enviarOQueFalta,
  fechar,
  recomecar,
} = useEnvioEmFatias({
  contagem: 'aplicadas',
  mensagemDeErro: () => t('RELACIONAMENTOS.LISTA.ETIQUETA.ERRO'),
  aoConcluir: faltam => emit('concluido', faltam),
});

const opcoes = computed(() =>
  etiquetas.value.map(nome => ({ value: nome, label: nome }))
);

const colocada = count =>
  t(
    'RELACIONAMENTOS.LISTA.ETIQUETA.APLICADA',
    { count, etiqueta: escolhida.value },
    count
  );

const abrir = async () => {
  recomecar();
  escolhida.value = '';
  faltaEscolher.value = false;
  try {
    etiquetas.value = await props.acoes.etiquetas();
  } catch {
    useAlert(t('RELACIONAMENTOS.COMUM.ERRO_GENERICO'));
    return;
  }
  dialogo.value?.open();
};

const colocar = lote =>
  props.acoes.aplicarEtiqueta({ ...lote, etiqueta: escolhida.value });

const aplicar = async () => {
  if (!escolhida.value) {
    faltaEscolher.value = true;
    campo.value?.querySelector('button')?.focus();
    return;
  }
  const feito = await enviarOQueFalta(props.pessoas, colocar);
  if (!feito || feito.erro || feito.deFora.length) return;
  useAlert(colocada(feito.feitas));
  dialogo.value?.close();
};

const aoConfirmar = () => (terminou.value ? dialogo.value?.close() : aplicar());

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    type="edit"
    width="sm"
    :confirm-button-label="
      rotuloDeConfirmar(
        t,
        resultado,
        t('RELACIONAMENTOS.LISTA.ETIQUETA.APLICAR')
      )
    "
    :cancel-button-label="rotuloDeCancelar(t, resultado)"
    :show-cancel-button="!terminou"
    :is-loading="enviando"
    @confirm="aoConfirmar"
    @close="fechar"
  >
    <TituloDoDialogo :titulo="t('RELACIONAMENTOS.LISTA.ETIQUETA.TITULO')" />
    <div data-relacionamentos="dialogo-etiqueta">
      <ResultadoDaAcao
        :andamento="andamento"
        :resultado="resultado"
        :frase="colocada"
      />
      <div v-if="!resultado" ref="campo" class="flex flex-col gap-2">
        <label :for="idDoCampo" class="text-sm font-medium text-n-slate-12">
          {{ t('RELACIONAMENTOS.LISTA.ETIQUETA.PERGUNTA') }}
        </label>
        <ChoiceSelect
          v-model="escolhida"
          :options="opcoes"
          :trigger-id="idDoCampo"
          :placeholder="t('RELACIONAMENTOS.LISTA.ETIQUETA.ESCOLHA')"
          :aria-label="t('RELACIONAMENTOS.LISTA.ETIQUETA.PERGUNTA')"
          :invalid="faltaEscolher"
          :described-by="idDoAviso"
        />
        <p
          :id="idDoAviso"
          role="alert"
          data-relacionamentos="etiqueta-falta"
          class="m-0 text-sm text-n-ruby-11"
        >
          {{
            faltaEscolher
              ? t('RELACIONAMENTOS.LISTA.ETIQUETA.FALTA_ESCOLHER')
              : ''
          }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
