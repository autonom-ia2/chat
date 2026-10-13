<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { ETAPA_DESLIGADA, ETAPA_PROPRIA, textoDoJeito } from './passagem';

// #1385 — cada etapa numa linha: o que vale nela e um "Alterar". A etapa feita do seu jeito diz, em poucas palavras,
// como chama a equipe; o detalhe fica na tela da etapa. Nome e selo dividem a linha quando cabem, para um funil de oito
// ou mais etapas não virar uma lista comprida; no celular o selo desce para baixo do nome.
defineProps({
  etapas: { type: Array, required: true },
  pessoas: { type: Array, default: () => [] },
  funilLigado: { type: Boolean, required: true },
  incompletas: { type: Array, default: () => [] },
  mostrarErros: { type: Boolean, default: false },
});

defineEmits(['alterar']);

const { t } = useI18n();
const E = 'CRM_KANBAN.PASSAGEM.ETAPAS';

const selo = (etapa, funilLigado) => {
  if (etapa.modo === ETAPA_PROPRIA)
    return { texto: t(`${E}.SELO_PROPRIA`), tom: 'bg-n-blue-3 text-n-blue-11' };
  if (etapa.modo === ETAPA_DESLIGADA)
    return {
      texto: t(`${E}.SELO_NAO_PASSA`),
      tom: 'bg-n-slate-3 text-n-slate-11',
    };
  return funilLigado
    ? { texto: t(`${E}.SELO_IGUAL`), tom: 'bg-n-teal-3 text-n-teal-11' }
    : { texto: t(`${E}.SELO_NAO_PASSA`), tom: 'bg-n-slate-3 text-n-slate-11' };
};
</script>

<template>
  <section class="flex flex-col gap-4" aria-labelledby="passagem-etapas">
    <div class="flex flex-col gap-1">
      <h2
        id="passagem-etapas"
        class="mb-0 text-lg font-semibold text-n-slate-12"
      >
        {{ t(`${E}.TITULO`) }}
      </h2>
      <p class="mb-0 text-[0.9375rem] text-n-slate-11">{{ t(`${E}.AJUDA`) }}</p>
    </div>
    <p
      v-if="!etapas.length"
      class="mb-0 rounded-2xl border border-dashed border-n-slate-6 p-5 text-[0.9375rem] text-n-slate-11"
    >
      {{ t(`${E}.VAZIO`) }}
    </p>
    <ol v-else class="m-0 flex list-none flex-col gap-2 p-0">
      <li
        v-for="(etapa, posicao) in etapas"
        :key="etapa.id"
        :data-etapa="etapa.nome"
        class="flex items-center gap-3 rounded-2xl border bg-n-solid-1 px-3 py-2.5 shadow-sm sm:px-4"
        :class="
          mostrarErros && incompletas.includes(etapa.id)
            ? 'border-n-ruby-8'
            : 'border-n-weak'
        "
      >
        <span
          class="grid size-9 shrink-0 place-items-center rounded-xl bg-n-alpha-2 text-[0.9375rem] font-bold text-n-slate-11"
          aria-hidden="true"
        >
          {{ posicao + 1 }}
        </span>
        <span
          class="flex min-w-0 flex-1 flex-wrap items-center gap-x-2 gap-y-1"
        >
          <span
            :title="etapa.nome"
            class="max-w-full truncate text-base font-semibold text-n-slate-12"
            >{{ etapa.nome }}</span
          >
          <span
            class="shrink-0 rounded-lg px-2 py-0.5 text-sm font-medium"
            :class="selo(etapa, funilLigado).tom"
          >
            {{ selo(etapa, funilLigado).texto }}
          </span>
          <span
            v-if="etapa.modo === ETAPA_PROPRIA"
            class="text-sm text-n-slate-11"
          >
            {{ textoDoJeito(t, etapa.regra, pessoas) }}
          </span>
          <span
            v-if="mostrarErros && incompletas.includes(etapa.id)"
            role="alert"
            class="basis-full text-sm font-medium text-n-ruby-11"
          >
            {{ t('CRM_KANBAN.PASSAGEM.FALTA_PESSOA') }}
          </span>
        </span>
        <Button
          :label="t('CRM_KANBAN.PASSAGEM.ALTERAR')"
          :aria-label="t(`${E}.ALTERAR_ETAPA`, { etapa: etapa.nome })"
          icon="i-lucide-pencil"
          slate
          faded
          class="!min-h-11 shrink-0"
          @click="$emit('alterar', etapa)"
        />
      </li>
    </ol>
  </section>
</template>
