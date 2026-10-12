<script setup>
import { computed } from 'vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { corDoFunil } from '../helpers/caixa';

// #1149 — etapa 1: que tipos de assunto chegam por esta caixa. Cada funil é um
// cartão marcável com o "Quando usar" dele. Com um funil só, a pessoa escolhe
// também a etapa em que o card começa (como hoje).
const props = defineProps({
  funis: { type: Array, required: true },
});

const pipelineIds = defineModel('pipelineIds', { type: Array, required: true });
const etapaInicial = defineModel('etapaInicial', {
  type: [Number, null],
  default: null,
});

const marcado = funil => pipelineIds.value.includes(funil.id);

const alternar = funil => {
  pipelineIds.value = marcado(funil)
    ? pipelineIds.value.filter(id => id !== funil.id)
    : [...pipelineIds.value, funil.id];
};

const unico = computed(() =>
  pipelineIds.value.length === 1
    ? props.funis.find(funil => funil.id === pipelineIds.value[0])
    : null
);

const etapas = computed(() =>
  (unico.value?.stages || []).map(etapa => ({
    value: etapa.id,
    label: etapa.name,
  }))
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="grid gap-3 md:grid-cols-2">
      <button
        v-for="funil in funis"
        :key="funil.id"
        type="button"
        role="checkbox"
        :aria-checked="marcado(funil)"
        data-funil
        class="flex min-h-11 items-start gap-4 rounded-2xl border-2 border-solid bg-n-solid-1 p-4 text-start transition-colors"
        :class="
          marcado(funil)
            ? 'border-n-blue-9 bg-n-blue-2'
            : 'border-n-weak hover:border-n-slate-7'
        "
        @click="alternar(funil)"
      >
        <span
          class="mt-0.5 grid size-6 shrink-0 place-items-center rounded-md border-2"
          :class="
            marcado(funil)
              ? 'border-n-blue-9 bg-n-blue-9 text-white'
              : 'border-n-slate-7'
          "
          aria-hidden="true"
        >
          <span v-if="marcado(funil)" class="i-lucide-check size-4" />
        </span>
        <span class="flex min-w-0 flex-col gap-1">
          <span
            class="flex items-center gap-2 text-base font-semibold text-n-slate-12"
          >
            <span
              class="size-2.5 rounded-full"
              :class="corDoFunil(funis, funil.id)"
              aria-hidden="true"
            />
            {{ funil.name }}
          </span>
          <span class="text-[0.9375rem] text-n-slate-11">
            {{ funil.when_to_use }}
          </span>
          <span class="text-sm text-n-slate-10">
            {{ $t(`CRM_CAIXAS.FUNIS.TIPO_${funil.kind.toUpperCase()}`) }}
          </span>
        </span>
      </button>
    </div>

    <div
      v-if="unico"
      class="flex flex-col gap-2 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
    >
      <span
        id="caixa-etapa-inicial"
        class="text-[0.9375rem] font-medium text-n-slate-12"
      >
        {{ $t('CRM_CAIXAS.FUNIS.ETAPA_INICIAL', { funil: unico.name }) }}
      </span>
      <ChoiceSelect
        v-model="etapaInicial"
        :options="etapas"
        :aria-label="
          $t('CRM_CAIXAS.FUNIS.ETAPA_INICIAL', { funil: unico.name })
        "
        :placeholder="etapas[0]?.label"
        class="max-w-xs"
      />
    </div>

    <p
      v-if="!pipelineIds.length"
      role="status"
      class="mb-0 flex items-start gap-2 rounded-xl bg-n-alpha-2 px-4 py-3 text-[0.9375rem] text-n-slate-12"
    >
      <span class="i-lucide-info mt-0.5 size-4 shrink-0" aria-hidden="true" />
      {{ $t('CRM_CAIXAS.FUNIS.NENHUM') }}
    </p>
  </div>
</template>
