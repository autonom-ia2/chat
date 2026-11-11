<script setup>
import { useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import ResultadoDaAcao from './ResultadoDaAcao.vue';
import {
  resumoDoQueFoiFeito,
  rotuloDeCancelar,
  rotuloDeConfirmar,
  useEnvioEmFatias,
} from '../../lista/useEnvioEmFatias';

// #2894 — confirmação destrutiva: "Apagar 12 pessoas? Isto não volta." Tocar
// fora não fecha (só Esc e Cancelar). Enquanto apaga: "50 de 120". Deu tudo
// certo: avisa e fecha. Se alguém não saiu ou parou no meio, o diálogo fica
// aberto e diz quem, por quê e quantas ainda não foram. Fechar no meio do
// trabalho para depois da fatia em andamento.
const props = defineProps({
  pessoas: { type: Array, required: true },
  acoes: { type: Object, required: true },
});
const emit = defineEmits(['concluido']);

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const apagadas = count =>
  t('RELACIONAMENTOS.LISTA.APAGAR.APAGADAS', { count }, count);
const {
  enviando,
  andamento,
  resultado,
  terminou,
  enviarOQueFalta,
  fechar,
  recomecar,
} = useEnvioEmFatias({
  contagem: 'apagadas',
  mensagemDeErro: () => t('RELACIONAMENTOS.LISTA.APAGAR.ERRO'),
  aoConcluir: faltam => emit('concluido', faltam),
  resumo: resumoDoQueFoiFeito(t, apagadas),
});

const abrir = () => {
  recomecar();
  dialogo.value?.open();
};

const apagar = async () => {
  const feito = await enviarOQueFalta(props.pessoas, lote =>
    props.acoes.apagar(lote)
  );
  if (!feito || feito.erro || feito.deFora.length) return;
  useAlert(apagadas(feito.feitas));
  dialogo.value?.close();
};

const aoConfirmar = () => (terminou.value ? dialogo.value?.close() : apagar());

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    :type="terminou ? 'edit' : 'alert'"
    width="sm"
    :confirm-button-label="
      rotuloDeConfirmar(
        t,
        resultado,
        t('RELACIONAMENTOS.LISTA.APAGAR.CONFIRMAR')
      )
    "
    :cancel-button-label="rotuloDeCancelar(t, resultado)"
    :show-cancel-button="!terminou"
    :is-loading="enviando"
    :close-on-outside-click="false"
    @confirm="aoConfirmar"
    @close="fechar"
  >
    <div data-relacionamentos="dialogo-apagar" class="flex flex-col gap-2">
      <TituloDoDialogo
        v-if="!resultado"
        :titulo="
          t(
            'RELACIONAMENTOS.LISTA.APAGAR.TITULO',
            { count: pessoas.length },
            pessoas.length
          )
        "
        :aviso="t('RELACIONAMENTOS.LISTA.APAGAR.AVISO')"
      />
      <ResultadoDaAcao
        :andamento="andamento"
        :resultado="resultado"
        :frase="apagadas"
      />
    </div>
  </Dialog>
</template>
