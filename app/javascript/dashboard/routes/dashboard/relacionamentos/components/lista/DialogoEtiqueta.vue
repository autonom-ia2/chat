<script setup>
import { computed, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import { useEnvio } from '../../lista/useEnvio';

// #2894 — diálogo pequeno: escolher uma etiqueta e colocar nas pessoas
// marcadas. Nada vem escolhido: o botão só liga depois da escolha.
const props = defineProps({
  pessoas: { type: Array, required: true },
  acoes: { type: Object, required: true },
});
const emit = defineEmits(['concluido']);

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const idDoCampo = useId();

const etiquetas = ref([]);
const escolhida = ref('');
const { enviando, enviar } = useEnvio(() =>
  t('RELACIONAMENTOS.LISTA.ETIQUETA.ERRO')
);

const opcoes = computed(() =>
  etiquetas.value.map(nome => ({ value: nome, label: nome }))
);

const abrir = async () => {
  escolhida.value = '';
  try {
    etiquetas.value = await props.acoes.etiquetas();
  } catch {
    useAlert(t('RELACIONAMENTOS.COMUM.ERRO_GENERICO'));
    return;
  }
  dialogo.value?.open();
};

const aplicar = async () => {
  const etiqueta = escolhida.value;
  const feito = await enviar(() =>
    props.acoes.aplicarEtiqueta({ pessoas: props.pessoas, etiqueta })
  );
  if (!feito) return;
  const count = feito.aplicadas;
  useAlert(
    t('RELACIONAMENTOS.LISTA.ETIQUETA.APLICADA', { count, etiqueta }, count)
  );
  dialogo.value?.close();
  emit('concluido');
};

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    type="edit"
    width="sm"
    :confirm-button-label="t('RELACIONAMENTOS.LISTA.ETIQUETA.APLICAR')"
    :cancel-button-label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
    :disable-confirm-button="!escolhida"
    :is-loading="enviando"
    @confirm="aplicar"
  >
    <TituloDoDialogo :titulo="t('RELACIONAMENTOS.LISTA.ETIQUETA.TITULO')" />
    <div data-relacionamentos="dialogo-etiqueta" class="flex flex-col gap-2">
      <label :for="idDoCampo" class="text-sm font-medium text-n-slate-12">
        {{ t('RELACIONAMENTOS.LISTA.ETIQUETA.PERGUNTA') }}
      </label>
      <ChoiceSelect
        v-model="escolhida"
        :options="opcoes"
        :trigger-id="idDoCampo"
        :placeholder="t('RELACIONAMENTOS.LISTA.ETIQUETA.ESCOLHA')"
        :aria-label="t('RELACIONAMENTOS.LISTA.ETIQUETA.PERGUNTA')"
      />
    </div>
  </Dialog>
</template>
