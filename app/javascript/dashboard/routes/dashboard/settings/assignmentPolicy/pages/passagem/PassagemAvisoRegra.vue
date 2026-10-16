<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { juntarNomes, nomeDe } from './passagem';

// #1140 (correção 3) — a regra está salva, mas não vai rodar como a tela promete: a IA do funil está desligada, ou a
// pessoa fixa não pode receber numa caixa (a regra do motor de entrega, lida do servidor). Um aviso amarelo, com uma
// frase por motivo.
const props = defineProps({
  semIa: { type: Boolean, default: false },
  fixas: { type: Array, default: () => [] },
  pessoas: { type: Array, default: () => [] },
  funilId: { type: Number, default: null },
});

const { t, locale } = useI18n();
const A = 'CRM_KANBAN.PASSAGEM.REGRA_NAO_RODA';

const frases = computed(() => [
  ...(props.semIa ? [t(`${A}.SEM_IA`)] : []),
  ...props.fixas.map(fixa => {
    const valores = {
      nome: nomeDe(props.pessoas, fixa.pessoaId) || t(`${A}.ALGUEM`),
      caixas: juntarNomes(fixa.caixas, locale.value),
      etapa: fixa.etapa,
    };
    return fixa.etapa
      ? t(`${A}.FIXA_ETAPA`, valores)
      : t(`${A}.FIXA_FUNIL`, valores);
  }),
]);
</script>

<template>
  <div
    data-aviso-regra
    class="flex flex-col items-start gap-3 rounded-2xl border border-dashed border-n-amber-8 bg-n-amber-2 p-4 sm:flex-row sm:items-center"
  >
    <span class="flex min-w-0 flex-1 items-start gap-3">
      <span
        class="i-lucide-triangle-alert mt-0.5 size-5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      <span class="flex min-w-0 flex-col gap-1">
        <strong class="text-[0.9375rem] font-semibold text-n-slate-12">
          {{ t(`${A}.TITULO`) }}
        </strong>
        <ul
          class="m-0 flex list-disc flex-col gap-1 ps-5 text-[0.9375rem] text-n-slate-12"
        >
          <li v-for="(frase, indice) in frases" :key="indice">{{ frase }}</li>
        </ul>
      </span>
    </span>
    <Button
      v-if="semIa"
      :label="t('CRM_KANBAN.PASSAGEM.AVISOS.BOTAO_FUNIL')"
      icon="i-lucide-kanban"
      amber
      class="!min-h-11 shrink-0"
      @click="
        $router.push({
          name: 'crm_kanban_index',
          ...(funilId ? { query: { pipeline_id: String(funilId) } } : {}),
        })
      "
    />
  </div>
</template>
