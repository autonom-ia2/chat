<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  FALTAS,
  comOFunil,
  etapasDoFunil,
  funilSemEtapa,
} from '../../../carteira/ajustesDaRenovacao';

// #2898 — "Onde ficam as renovações?": o funil da conta em que a renovação de
// cada seguro aparece e a etapa em que ela entra. Escolher o funil já escolhe a
// primeira etapa dele. A conta sem funil nenhum lê o que fazer e ganha o
// caminho até o CRM: não há lista vazia nem botão desligado. O funil escolhido
// que não tem etapa nenhuma também: no lugar de uma escolha vazia, a tela diz
// isso e oferece o CRM (a pessoa cria a etapa lá, ou escolhe outro funil aqui).
//   v-model: { funilId, etapaId, ... } (o resto dos ajustes passa direto)
const props = defineProps({
  modelValue: { type: Object, required: true },
  // [{ id, nome, etapas: [{ id, nome }] }]
  funis: { type: Array, default: () => [] },
  // O que falta (FALTAS) e o id do aviso que diz isso, quando há.
  falta: { type: String, default: '' },
  idDoAviso: { type: String, default: undefined },
});
const emit = defineEmits(['update:modelValue', 'abrirCrm']);

const { t } = useI18n();
const to = chave => t(`RELACIONAMENTOS_CARTEIRA.AJUSTES.ONDE.${chave}`);
const id = useId();

const paraEscolher = lista =>
  lista.map(({ id: value, nome }) => ({ value, label: nome }));
const opcoesDeFunil = computed(() => paraEscolher(props.funis));
const opcoesDeEtapa = computed(() =>
  paraEscolher(etapasDoFunil(props.funis, props.modelValue.funilId))
);

const semEtapa = computed(() =>
  funilSemEtapa(props.funis, props.modelValue.funilId)
);
// O funil é o campo a mexer também quando o escolhido não tem etapa.
const FALTA_NO_FUNIL = [FALTAS.FUNIL, FALTAS.SEM_ETAPA];
const faltaNoFunil = computed(() => FALTA_NO_FUNIL.includes(props.falta));

// Leva o foco ao que falta (o botão de quem usa diz o que é).
const CAMPOS = {
  [FALTAS.FUNIL]: 'funil',
  [FALTAS.SEM_ETAPA]: 'funil',
  [FALTAS.ETAPA]: 'etapa',
};
defineExpose({
  focar: falta => document.getElementById(`${id}-${CAMPOS[falta]}`)?.focus(),
});
</script>

<template>
  <div
    v-if="!funis.length"
    data-carteira="sem-funil"
    class="flex flex-col items-start gap-4"
  >
    <p class="m-0 text-base text-n-slate-12">{{ to('SEM_FUNIL') }}</p>
    <Button
      slate
      faded
      size="lg"
      data-carteira="abrir-crm"
      :label="to('ABRIR_CRM')"
      @click="emit('abrirCrm')"
    />
  </div>
  <div v-else class="grid gap-4 sm:grid-cols-2">
    <div data-carteira="escolher-funil" class="flex flex-col min-w-0 gap-2">
      <label :for="`${id}-funil`" class="text-base text-n-slate-12">
        {{ to('FUNIL') }}
      </label>
      <ChoiceSelect
        :trigger-id="`${id}-funil`"
        :model-value="modelValue.funilId"
        :options="opcoesDeFunil"
        :aria-label="to('FUNIL')"
        :placeholder="to('ESCOLHA_O_FUNIL')"
        :invalid="faltaNoFunil"
        :described-by="faltaNoFunil ? idDoAviso : undefined"
        @update:model-value="
          emit('update:modelValue', comOFunil(modelValue, funis, $event))
        "
      />
    </div>
    <div
      v-if="semEtapa"
      data-carteira="funil-sem-etapa"
      class="flex flex-col items-start min-w-0 gap-3"
    >
      <p class="m-0 text-base text-n-slate-12">{{ to('SEM_ETAPA') }}</p>
      <Button
        slate
        faded
        size="lg"
        data-carteira="abrir-crm"
        :label="to('ABRIR_CRM')"
        @click="emit('abrirCrm')"
      />
    </div>
    <div
      v-else-if="modelValue.funilId"
      data-carteira="escolher-etapa"
      class="flex flex-col min-w-0 gap-2"
    >
      <label :for="`${id}-etapa`" class="text-base text-n-slate-12">
        {{ to('ETAPA') }}
      </label>
      <ChoiceSelect
        :trigger-id="`${id}-etapa`"
        :model-value="modelValue.etapaId"
        :options="opcoesDeEtapa"
        :aria-label="to('ETAPA')"
        :placeholder="to('ESCOLHA_A_ETAPA')"
        :invalid="falta === FALTAS.ETAPA"
        :described-by="falta === FALTAS.ETAPA ? idDoAviso : undefined"
        @update:model-value="
          emit('update:modelValue', { ...modelValue, etapaId: $event })
        "
      />
    </div>
    <p class="m-0 text-sm sm:col-span-2 text-n-slate-11">
      {{ to('APOIO') }}
    </p>
  </div>
</template>
