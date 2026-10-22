<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { textoDoFechamento } from '../sugestaoDeFechar';

// #1423 — em que etapa o cliente está. Tocar numa etapa move na hora, como
// hoje (RS-02); a lista é a do funil do card, não a do quadro (ET-01). Abaixo,
// a leitura da conversa sugere a etapa (IA-01): Mover ou Deixar como está.
const props = defineProps({
  etapas: { type: Array, required: true },
  atual: { type: [Number, String], default: null },
  podeMover: { type: Boolean, default: false },
  movendo: { type: Boolean, default: false },
  leitura: { type: Boolean, default: false },
  podeIa: { type: Boolean, default: false },
  sugestao: { type: Object, default: null },
  carregando: { type: Boolean, default: false },
  lendo: { type: Boolean, default: false },
  respondendo: { type: Boolean, default: false },
  aviso: { type: String, default: '' },
});
defineEmits(['mover', 'ler', 'aceitar', 'dispensar']);

const { t } = useI18n();
const E = 'CRM_CARD.ETAPA';
// F3: a sugestão de fechar o card troca o texto e o botão; não marca etapa.
const fechar = computed(() => textoDoFechamento(props.sugestao));
const travada = computed(
  () => !props.podeMover || props.movendo || !props.etapas.length
);
</script>

<template>
  <section class="flex flex-col gap-3" data-tela="etapa">
    <h3 class="mb-0 text-base font-semibold text-n-slate-12">
      {{ t(`${E}.ESCOLHA`) }}
    </h3>
    <p v-if="!podeMover" class="mb-0 text-sm text-n-slate-11">
      {{ t(`${E}.SO_LEITURA`) }}
    </p>
    <p
      v-else-if="!etapas.length"
      role="status"
      class="mb-0 flex items-center gap-2 text-sm text-n-slate-11"
    >
      <span class="i-lucide-loader-2 size-4 animate-spin" aria-hidden="true" />
      {{ t('CRM_CARD.CARREGANDO') }}
    </p>
    <ol
      :aria-label="t(`${E}.ESCOLHA`)"
      class="m-0 flex list-none flex-col gap-2 p-0"
    >
      <li v-for="(etapa, indice) in etapas" :key="etapa.id">
        <button
          type="button"
          :data-etapa="etapa.name"
          :aria-current="etapa.id === atual ? 'step' : undefined"
          :disabled="travada && etapa.id !== atual"
          class="flex min-h-14 w-full items-center gap-3 rounded-2xl bg-n-solid-1 px-4 ring-1 ring-inset text-start transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 disabled:cursor-not-allowed"
          :class="
            etapa.id === atual
              ? 'bg-n-blue-2 ring-2 ring-n-blue-8'
              : 'ring-n-weak hover:ring-n-slate-7 disabled:opacity-60'
          "
          @click="etapa.id !== atual && !travada && $emit('mover', etapa.id)"
        >
          <span
            class="grid size-7 shrink-0 place-items-center rounded-full text-sm font-bold"
            :class="
              etapa.id === atual
                ? 'bg-n-blue-9 text-white'
                : 'bg-n-alpha-2 text-n-slate-11'
            "
          >
            {{ indice + 1 }}
          </span>
          <span
            class="h-6 w-1 shrink-0 rounded-full"
            :style="{ backgroundColor: etapa.color }"
            aria-hidden="true"
          />
          <span class="min-w-0 flex-1 text-base text-n-slate-12">
            {{ etapa.name }}
          </span>
          <span
            v-if="etapa.id === atual"
            class="shrink-0 text-sm font-semibold text-n-blue-11"
          >
            {{ t('CRM_CARD.LADO.ESTA_AQUI') }}
          </span>
          <span
            v-else-if="!fechar && sugestao?.to_stage_id === etapa.id"
            class="shrink-0 rounded-lg bg-n-iris-3 px-2 py-0.5 text-xs font-semibold text-n-iris-11"
          >
            {{ t(`${E}.SUGERIDA`) }}
          </span>
          <span v-if="movendo && etapa.id !== atual" class="sr-only">
            {{ t(`${E}.MOVENDO`) }}
          </span>
        </button>
      </li>
    </ol>
    <p class="mb-0 text-sm text-n-slate-11">{{ t(`${E}.NA_HORA`) }}</p>

    <section
      v-if="leitura"
      data-etapa-leitura
      class="mt-3 flex flex-col gap-3 rounded-2xl border border-dashed border-n-iris-7 bg-n-iris-2 p-4"
    >
      <h4
        class="mb-0 flex items-center gap-2 text-base font-semibold text-n-slate-12"
      >
        <span
          class="i-lucide-sparkles size-4 text-n-iris-11"
          aria-hidden="true"
        />
        {{ t(`${E}.LEITURA`) }}
      </h4>
      <p
        v-if="carregando || lendo"
        role="status"
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ t(lendo ? `${E}.LENDO` : 'CRM_CARD.CARREGANDO') }}
      </p>
      <template v-else-if="sugestao">
        <p class="mb-0 text-[0.9375rem] text-n-slate-12">
          {{
            fechar
              ? t(fechar.frase, {
                  motivo: fechar.motivo ? t(fechar.motivo) : '',
                })
              : t(`${E}.ACHAMOS`, { etapa: sugestao.to_stage_name })
          }}
        </p>
        <p v-if="sugestao.reasoning" class="mb-0 text-sm text-n-slate-11">
          {{ sugestao.reasoning }}
        </p>
        <p v-if="fechar?.retorno" class="mb-0 text-sm text-n-slate-11">
          {{ t(fechar.retorno) }}
        </p>
        <div v-if="podeIa" class="flex flex-wrap gap-2">
          <Button
            :label="
              fechar
                ? t(fechar.botao)
                : t('CRM_CARD.PASSO.MOVER', { etapa: sugestao.to_stage_name })
            "
            icon="i-lucide-arrow-right"
            slate
            outline
            class="!min-h-11 !outline-n-weak"
            :is-loading="respondendo"
            @click="$emit('aceitar')"
          />
          <Button
            :label="t('CRM_CARD.PASSO.DEIXAR')"
            slate
            ghost
            class="!min-h-11"
            :disabled="respondendo"
            @click="$emit('dispensar')"
          />
        </div>
      </template>
      <p v-else-if="aviso" class="mb-0 text-sm text-n-slate-12">{{ aviso }}</p>
      <p v-else class="mb-0 text-sm text-n-slate-11">
        {{ t(`${E}.SEM_SUGESTAO`) }}
      </p>
      <Button
        v-if="podeIa && !lendo"
        data-etapa-ler
        :label="t(`${E}.LER`)"
        icon="i-lucide-refresh-cw"
        slate
        ghost
        class="!min-h-11 w-fit"
        @click="$emit('ler')"
      />
    </section>
  </section>
</template>
