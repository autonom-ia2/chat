<script setup>
import { computed, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CartoesDeEscolha from '../../trazer/CartoesDeEscolha.vue';
import {
  FALTAS,
  ONDE,
  comOFunil,
  quantosEntram,
} from '../../../carteira/ajustesDaRenovacao';
import CampoDeDias from './CampoDeDias.vue';

// #2897 — "Onde ficam as renovações?": criar o funil Renovação ou usar um que a
// conta já tem (funil e etapa), e quantos dias antes do fim a renovação aparece.
// A linha de efeito muda com o número. A mesma peça serve o passo de trazer
// seguros e o primeiro cartão de "Como as renovações andam". Quem não pode
// mexer em funis só lê a escolha de agora.
//   v-model: { onde, funil, etapa, dias }
const props = defineProps({
  modelValue: { type: Object, required: true },
  funis: { type: Array, default: () => [] },
  // Em quantos dias cada seguro termina (a linha "com N dias, X entram").
  vencimentos: { type: Array, default: () => [] },
  semPermissao: { type: Boolean, default: false },
  // O que falta (FALTAS) e o id do aviso que diz isso, quando há.
  falta: { type: String, default: '' },
  idDoAviso: { type: String, default: undefined },
  rotuloId: { type: String, required: true },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const to = (chave, valores, plural) =>
  t(`RELACIONAMENTOS_CARTEIRA.AJUSTES.ONDE.${chave}`, valores, plural);
const id = useId();
const raiz = useTemplateRef('raiz');

const mudar = mudanca =>
  emit('update:modelValue', { ...props.modelValue, ...mudanca });

const opcoes = computed(() => [
  {
    id: ONDE.CRIAR,
    rotulo: to('CRIAR'),
    descricao: to('CRIAR_APOIO'),
    atributos: { 'data-carteira': 'criar-funil' },
  },
  {
    id: ONDE.USAR,
    rotulo: to('USAR'),
    atributos: { 'data-carteira': 'usar-funil' },
  },
]);
const usaFunilDaConta = computed(() => props.modelValue.onde === ONDE.USAR);
const opcoesDeFunil = computed(() =>
  props.funis.map(({ nome }) => ({ value: nome, label: nome }))
);
const opcoesDeEtapa = computed(() =>
  (
    props.funis.find(funil => funil.nome === props.modelValue.funil)?.etapas ??
    []
  ).map(etapa => ({ value: etapa, label: etapa }))
);

const efeito = computed(() => {
  const { dias } = props.modelValue;
  if (!dias) return '';
  const entram = quantosEntram(props.vencimentos, dias);
  return `${to('COM_DIAS', { count: dias }, dias)} ${to('ENTRAM', { count: entram }, entram)}`;
});
const escolhaDeHoje = computed(() => {
  const { funil, dias } = props.modelValue;
  return to(
    'HOJE',
    {
      funil: usaFunilDaConta.value ? funil : to('FUNIL_RENOVACAO'),
      count: dias,
    },
    dias
  );
});

// Leva o foco ao que falta (o botão de quem usa diz o que é).
const ALVOS = {
  [FALTAS.ONDE]: () => raiz.value?.querySelector('[role="radio"]'),
  [FALTAS.FUNIL]: () => document.getElementById(`${id}-funil`),
  [FALTAS.DIAS]: () => document.getElementById(`${id}-dias`),
};
defineExpose({ focar: falta => ALVOS[falta]?.()?.focus() });
</script>

<template>
  <div ref="raiz" class="flex flex-col gap-6">
    <template v-if="semPermissao">
      <p data-carteira="escolha-de-hoje" class="m-0 text-base text-n-slate-12">
        {{ escolhaDeHoje }}
      </p>
      <Banner color="amber" data-carteira="sem-permissao-de-funil">
        {{ to('SEM_PERMISSAO') }}
      </Banner>
    </template>
    <template v-else>
      <CartoesDeEscolha
        :opcoes="opcoes"
        :model-value="modelValue.onde"
        :rotulo-id="rotuloId"
        :invalido="falta === FALTAS.ONDE"
        :descrito-por="falta === FALTAS.ONDE ? idDoAviso : undefined"
        @update:model-value="mudar({ onde: $event })"
      />
      <div v-if="usaFunilDaConta" class="grid gap-4 sm:grid-cols-2">
        <div data-carteira="escolher-funil" class="flex flex-col gap-2">
          <label :for="`${id}-funil`" class="text-base text-n-slate-12">
            {{ to('FUNIL') }}
          </label>
          <ChoiceSelect
            :trigger-id="`${id}-funil`"
            :model-value="modelValue.funil"
            :options="opcoesDeFunil"
            :aria-label="to('FUNIL')"
            :invalid="falta === FALTAS.FUNIL"
            :described-by="falta === FALTAS.FUNIL ? idDoAviso : undefined"
            @update:model-value="
              emit('update:modelValue', comOFunil(modelValue, funis, $event))
            "
          />
        </div>
        <div
          v-if="modelValue.funil"
          data-carteira="escolher-etapa"
          class="flex flex-col gap-2"
        >
          <label :for="`${id}-etapa`" class="text-base text-n-slate-12">
            {{ to('ETAPA') }}
          </label>
          <ChoiceSelect
            :trigger-id="`${id}-etapa`"
            :model-value="modelValue.etapa"
            :options="opcoesDeEtapa"
            :aria-label="to('ETAPA')"
            @update:model-value="mudar({ etapa: $event })"
          />
        </div>
        <p class="m-0 text-sm sm:col-span-2 text-n-slate-11">
          {{ to('QUEM_CUIDA') }}
        </p>
      </div>
      <div class="flex flex-col gap-2">
        <label :for="`${id}-dias`" class="text-base text-n-slate-12">
          {{ to('DIAS') }}
        </label>
        <div data-carteira="dias-antes">
          <CampoDeDias
            :id="`${id}-dias`"
            :model-value="modelValue.dias"
            :invalido="falta === FALTAS.DIAS"
            :descrito-por="falta === FALTAS.DIAS ? idDoAviso : undefined"
            @update:model-value="mudar({ dias: $event })"
          />
        </div>
        <p
          data-carteira="efeito-dias"
          aria-live="polite"
          class="m-0 text-sm text-n-slate-11"
        >
          {{ efeito }}
        </p>
      </div>
    </template>
  </div>
</template>
