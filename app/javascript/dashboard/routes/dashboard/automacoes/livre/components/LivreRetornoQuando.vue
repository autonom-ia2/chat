<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreDuracao from './LivreDuracao.vue';
import { DURACAO_PADRAO } from '../catalogo';

// G57 (#2769) — quando vence o retorno: daqui a um tempo (o `daqui`) ou hoje ou
// amanhã, numa hora ou no fim do dia (o `quando`), no fuso da conta. A peça
// cuida dos dois campos: o passo leva um ou o outro.
const props = defineProps({
  rotulo: { type: String, required: true },
  daqui: { type: Object, default: null },
  quando: { type: Object, default: null },
  unidades: { type: Array, required: true },
});

const emit = defineEmits(['update']);

const { t } = useI18n();
const R = 'AUTOMACAO_LIVRE.RETORNO.QUANDO';
const FIM_DO_DIA = 'fim';
const HORAS = Array.from({ length: 24 }, (_, hora) => hora);

const modo = computed(() => props.quando?.dia || 'daqui');
const opcoesDoModo = computed(() =>
  ['daqui', 'hoje', 'amanha'].map(valor => ({
    value: valor,
    label: t(`${R}.MODOS.${valor.toUpperCase()}`),
  }))
);
const opcoesDaHora = computed(() => [
  { value: FIM_DO_DIA, label: t(`${R}.FIM_DO_DIA`) },
  ...HORAS.map(hora => ({
    value: String(hora),
    label: t(`${R}.HORA_ITEM`, { hora }),
  })),
]);

const mudarModo = novo => {
  if (novo === 'daqui') {
    emit('update', {
      daqui: props.daqui || { ...DURACAO_PADRAO },
      quando: null,
    });
    return;
  }
  emit('update', {
    daqui: null,
    quando: { ...(props.quando || {}), dia: novo },
  });
};

const mudarHora = novo => {
  const { hora: _antiga, ...resto } = props.quando || {};
  emit('update', {
    daqui: null,
    quando: novo === FIM_DO_DIA ? resto : { ...resto, hora: Number(novo) },
  });
};
</script>

<template>
  <fieldset class="flex flex-col gap-3" data-peca="quando_do_retorno">
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <ChoiceSelect
      :model-value="modo"
      :aria-label="rotulo"
      :options="opcoesDoModo"
      data-quando-modo
      @update:model-value="mudarModo"
    />
    <LivreDuracao
      v-if="modo === 'daqui'"
      :rotulo="$t(`${R}.DAQUI_QUANTO`)"
      :model-value="daqui"
      :unidades="unidades"
      @update:model-value="
        novo => emit('update', { daqui: novo, quando: null })
      "
    />
    <div v-else class="flex flex-col gap-1.5">
      <ChoiceSelect
        :model-value="
          Number.isInteger(quando?.hora) ? String(quando.hora) : FIM_DO_DIA
        "
        :aria-label="$t(`${R}.QUE_HORAS`)"
        :options="opcoesDaHora"
        data-quando-hora
        @update:model-value="mudarHora"
      />
      <p class="text-sm text-n-slate-11">{{ $t(`${R}.DICA`) }}</p>
    </div>
  </fieldset>
</template>
