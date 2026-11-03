<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { GRUPOS, gatilhoDe } from '../gatilhosDemo';

// #2499 (F6+F8) — o gatilho no "Alterar": o seletor agrupado (conversa,
// mensagem, card do funil, tempo, reunião) e os campos que cada gatilho pede
// (etapa, dias, campo de data, antes ou depois, hora, frequência). Os gatilhos
// de card só chegam aqui para quem pode mexer no funil.
const props = defineProps({
  modelValue: { type: Object, default: null },
  gatilhos: { type: Array, required: true },
  // { etapas: [{ label, options }], funis, camposDoCard, camposDoContato }
  escolhas: { type: Object, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const G = 'AUTOMACAO_LIVRE.GATILHOS_F6';
const idTipo = useId();

const grupos = computed(() =>
  GRUPOS.map(grupo => ({
    label: t(`${G}.GRUPOS.${grupo}`),
    options: props.gatilhos
      .filter(item => item.grupo === grupo)
      .map(item => ({ value: item.tipo, label: t(item.frase) })),
  })).filter(grupo => grupo.options.length)
);

const entrada = computed(() => gatilhoDe(props.modelValue?.tipo));
const parametros = computed(() => entrada.value?.parametros || []);

// Trocar o tipo apaga os campos do anterior (etapa, dias...), mas mantém os
// filtros: eles leem o alvo, e o salvar recusa o que o alvo novo não tem.
const trocarTipo = tipo => {
  const { filtros } = props.modelValue || {};
  emit('update:modelValue', filtros ? { tipo, filtros } : { tipo });
};
const mudar = (nome, valor) =>
  emit('update:modelValue', { ...(props.modelValue || {}), [nome]: valor });

const MAXIMO_DE_DIAS = 3650;
const lerDias = texto =>
  texto === ''
    ? null
    : Math.min(Math.max(Math.trunc(Number(texto)) || 1, 1), MAXIMO_DE_DIAS);

const opcoesDe = peca => {
  const lista = valores =>
    valores.map(([value, chave]) => ({ value, label: t(`${G}.${chave}`) }));
  if (peca === 'antes_depois')
    return lista([
      ['antes', 'ANTES'],
      ['depois', 'DEPOIS'],
      ['no_dia', 'NO_DIA'],
    ]);
  if (peca === 'frequencia')
    return lista([
      ['dia', 'FREQ.DIA'],
      ['semana', 'FREQ.SEMANA'],
      ['mes', 'FREQ.MES'],
    ]);
  if (peca === 'alvo_recorrente')
    return lista([
      ['cards', 'ALVO.CARDS'],
      ['contatos', 'ALVO.CONTATOS'],
    ]);
  if (peca === 'hora')
    return Array.from({ length: 24 }, (_, hora) => ({
      value: hora,
      label: `${String(hora).padStart(2, '0')}:00`,
    }));
  if (peca === 'dia' && props.modelValue?.frequencia === 'mes')
    return Array.from({ length: 28 }, (_, dia) => ({
      value: dia + 1,
      label: String(dia + 1),
    }));
  if (peca === 'dia')
    return ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB', 'DOM'].map((dia, i) => ({
      value: i + 1,
      label: t(`${G}.SEMANA.${dia}`),
    }));
  if (peca === 'funil') return props.escolhas.funis || [];
  if (peca === 'campo_data_card') return props.escolhas.camposDoCard || [];
  if (peca === 'campo_data_contato')
    return props.escolhas.camposDoContato || [];
  return [];
};

// "Todo dia" não pergunta o dia.
const visivel = parametro =>
  !(parametro.peca === 'dia' && props.modelValue?.frequencia === 'dia');
</script>

<template>
  <div class="flex flex-col gap-4" data-peca="gatilho">
    <div class="flex flex-col gap-1.5">
      <label :for="idTipo" class="text-sm font-medium text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIPO_GATILHO') }}
      </label>
      <ChoiceSelect
        :model-value="modelValue?.tipo || ''"
        :trigger-id="idTipo"
        :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIPO_GATILHO')"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :groups="grupos"
        @update:model-value="trocarTipo"
      />
    </div>

    <template v-for="parametro in parametros" :key="parametro.nome">
      <div
        v-if="visivel(parametro)"
        class="flex flex-col gap-1.5"
        :data-parametro="parametro.nome"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t(`${G}.PARAMETROS.${parametro.nome.toUpperCase()}`) }}
        </span>
        <Input
          v-if="parametro.peca === 'dias'"
          type="number"
          min="1"
          :max="String(MAXIMO_DE_DIAS)"
          :model-value="modelValue?.[parametro.nome] ?? ''"
          @update:model-value="texto => mudar(parametro.nome, lerDias(texto))"
        />
        <ChoiceSelect
          v-else-if="parametro.peca === 'etapa'"
          :model-value="modelValue?.[parametro.nome] ?? ''"
          :aria-label="$t(`${G}.PARAMETROS.${parametro.nome.toUpperCase()}`)"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :groups="escolhas.etapas || []"
          @update:model-value="valor => mudar(parametro.nome, valor)"
        />
        <ChoiceSelect
          v-else
          :model-value="modelValue?.[parametro.nome] ?? ''"
          :aria-label="$t(`${G}.PARAMETROS.${parametro.nome.toUpperCase()}`)"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="opcoesDe(parametro.peca)"
          @update:model-value="valor => mudar(parametro.nome, valor)"
        />
      </div>
    </template>

    <p
      v-if="entrada?.aviso"
      class="m-0 rounded-lg bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11"
    >
      {{ $t(`${G}.${entrada.aviso}`) }}
    </p>
    <p v-if="entrada?.grupo === 'TEMPO'" class="m-0 text-xs text-n-slate-11">
      {{ $t(`${G}.FUSO_DA_CONTA`) }}
    </p>
  </div>
</template>
