<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  ULTIMA_HORA,
  emMinutos,
  opcoesDeAbrir,
  opcoesDeFechar,
  diaValido,
} from './horarioDoCanal';

// #1619 — um dia do horário do canal (protótipo J1): marcar o dia, "o dia todo" ou as horas de
// abrir e fechar em 24 h (09:00), pelo ChoiceSelect do produto, nunca pelo <select> nativo.
// Em tela larga é uma linha de três colunas (dia, horário, total); no celular, empilha.
const props = defineProps({
  // { dia: 0..6, ligado, diaTodo, abre: 'HH:MM', fecha: 'HH:MM' }
  modelValue: { type: Object, required: true },
  desabilitado: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const NS = 'HORARIO_DO_CANAL.CANAL';

const nomeDoDia = computed(() => t(`${NS}.DIAS.D${props.modelValue.dia}`));
const atualizar = mudanca =>
  emit('update:modelValue', { ...props.modelValue, ...mudanca });

const abre = computed(() => opcoesDeAbrir(props.modelValue.abre));
const fecha = computed(() => opcoesDeFechar(props.modelValue.fecha));
const valido = computed(() => diaValido(props.modelValue));

const total = computed(() => {
  if (props.modelValue.diaTodo) return t(`${NS}.TOTAL_DIA_TODO`);
  const fim =
    props.modelValue.fecha === ULTIMA_HORA
      ? 1440
      : emMinutos(props.modelValue.fecha);
  const minutos = fim - emMinutos(props.modelValue.abre);
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  if (!h) return t(`${NS}.TOTAL_MINUTOS`, { m });
  return m
    ? t(`${NS}.TOTAL_HORAS_MINUTOS`, { h, m })
    : t(`${NS}.TOTAL_HORAS`, { h });
});
</script>

<template>
  <div
    data-dia
    class="grid gap-x-4 gap-y-2 px-4 py-3 md:grid-cols-[11rem_minmax(0,1fr)_4rem] md:items-center"
  >
    <label
      class="flex items-center gap-3 cursor-pointer min-h-11 w-fit text-body-main font-medium text-n-slate-12"
    >
      <Checkbox
        :model-value="modelValue.ligado"
        :disabled="desabilitado"
        @update:model-value="atualizar({ ligado: $event })"
      />
      {{ nomeDoDia }}
    </label>

    <div v-if="modelValue.ligado" class="flex flex-col gap-1.5 min-w-0">
      <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
        <label
          class="flex items-center gap-2 cursor-pointer min-h-11 text-body-main text-n-slate-12"
        >
          <Checkbox
            :model-value="modelValue.diaTodo"
            :disabled="desabilitado"
            @update:model-value="atualizar({ diaTodo: $event })"
          />
          {{ t(`${NS}.DIA_TODO`) }}
        </label>
        <div class="flex flex-wrap items-center gap-2">
          <div class="w-28">
            <ChoiceSelect
              :model-value="modelValue.abre"
              :options="abre"
              :aria-label="t(`${NS}.ABRE_AS`, { dia: nomeDoDia })"
              :disabled="desabilitado || modelValue.diaTodo"
              :invalid="!valido"
              @update:model-value="atualizar({ abre: $event })"
            />
          </div>
          <span class="text-body-main text-n-slate-11">
            {{ t(`${NS}.ATE`) }}
          </span>
          <div class="w-28">
            <ChoiceSelect
              :model-value="modelValue.fecha"
              :options="fecha"
              :aria-label="t(`${NS}.FECHA_AS`, { dia: nomeDoDia })"
              :disabled="desabilitado || modelValue.diaTodo"
              :invalid="!valido"
              @update:model-value="atualizar({ fecha: $event })"
            />
          </div>
        </div>
      </div>
      <p v-if="!valido" data-erro class="m-0 text-label-small text-n-ruby-11">
        {{ t(`${NS}.ERRO_HORAS`) }}
      </p>
    </div>
    <span v-else class="text-body-main text-n-slate-11">
      {{ t(`${NS}.FECHADO`) }}
    </span>

    <span
      v-if="modelValue.ligado && valido"
      data-total
      class="justify-self-start md:justify-self-end px-2 py-1 rounded-lg whitespace-nowrap text-label-small bg-n-blue-3 text-n-blue-11"
    >
      {{ total }}
    </span>
  </div>
</template>
