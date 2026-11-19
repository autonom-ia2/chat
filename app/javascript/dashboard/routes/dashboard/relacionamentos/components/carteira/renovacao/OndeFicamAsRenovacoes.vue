<script setup>
import { computed, useId } from 'vue';
import { useMediaQuery } from '@vueuse/core';
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
// #3057 — sem funil, quem pode criar funil no CRM (`podeCriar`) ganha o botão
// azul "Criar o funil de renovações para mim" (quem cria é a página), e "Abrir
// o CRM" vira um link ao lado. Quem não pode segue com o caminho até o CRM.
//   v-model: { funilId, etapaId, ... } (o resto dos ajustes passa direto)
const props = defineProps({
  modelValue: { type: Object, required: true },
  // [{ id, nome, etapas: [{ id, nome }] }]
  funis: { type: Array, default: () => [] },
  // O que falta (FALTAS) e o id do aviso que diz isso, quando há.
  falta: { type: String, default: '' },
  idDoAviso: { type: String, default: undefined },
  podeCriar: { type: Boolean, default: false },
  criando: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue', 'abrirCrm', 'criarFunil']);

const { t } = useI18n();
const to = chave => t(`RELACIONAMENTOS_CARTEIRA.AJUSTES.ONDE.${chave}`);
// #3057 — no celular o rótulo inteiro não cabe no botão (o Button corta com
// "…"): lá ele é "Criar o funil para mim".
const telaLarga = useMediaQuery('(min-width: 640px)');
const rotuloDeCriar = computed(() =>
  to(telaLarga.value ? 'CRIAR_FUNIL' : 'CRIAR_FUNIL_CURTO')
);
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
    <p class="m-0 text-base text-n-slate-12">
      {{ to(podeCriar ? 'SEM_FUNIL_CRIAR' : 'SEM_FUNIL') }}
    </p>
    <div
      v-if="podeCriar"
      class="flex flex-col items-start w-full gap-2 sm:flex-row sm:items-center sm:gap-6"
    >
      <Button
        size="lg"
        icon="i-lucide-plus"
        class="w-full sm:w-auto"
        data-carteira="criar-funil"
        :is-loading="criando"
        :label="rotuloDeCriar"
        @click="emit('criarFunil')"
      />
      <Button
        link
        size="lg"
        class="min-h-11"
        data-carteira="abrir-crm"
        :label="to('ABRIR_CRM')"
        @click="emit('abrirCrm')"
      />
    </div>
    <Button
      v-else
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
