<script setup>
import { useI18n } from 'vue-i18n';
import EscolhaRadio from './EscolhaRadio.vue';

// #1720 — a lista de canais de "Onde atende" (cartões-rádio), com o aviso de troca e o de leitura
// parcial. Fica solta na criação e, na gaveta da página, embaixo de "Sim, no canal:" (`recuada`).
// `troca`: o resultado do trocaNoCanal para a caixa escolhida, ou null.
defineProps({
  rotulo: { type: String, required: true },
  opcoes: { type: Array, required: true },
  modelValue: { type: Number, default: null },
  nome: { type: String, required: true },
  troca: { type: Object, default: null },
  todosOcupados: { type: Boolean, default: false },
  semLeitura: { type: Boolean, default: false },
  recuada: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const NS = 'AGENTS.JORNADA.ONDE_QUANDO';
</script>

<template>
  <div
    data-canais-primeiro
    class="flex flex-col gap-2"
    :class="recuada ? 'ps-4 ms-2.5 border-s-2 border-n-slate-6' : ''"
  >
    <p v-if="todosOcupados" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.TODOS_OCUPADOS`, { nome }) }}
    </p>
    <EscolhaRadio
      :rotulo="rotulo"
      :opcoes="opcoes"
      :model-value="modelValue"
      @update:model-value="emit('update:modelValue', $event)"
    />
    <p
      v-if="troca"
      data-troca
      class="flex items-start gap-2 p-3 m-0 text-sm rounded-xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
    >
      <span
        class="i-lucide-triangle-alert size-5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      <span class="flex flex-col gap-1">
        <span>
          {{ t(`${NS}.TROCA`, { outro: troca.nome, canal: troca.canal }) }}
        </span>
        <!-- #1366: era a última caixa dele, então ele para de atender. -->
        <strong
          v-if="troca.atendia && troca.ultimaCaixa"
          data-troca-para
          class="font-semibold"
        >
          {{ t(`${NS}.TROCA_PARA`, { outro: troca.nome }) }}
        </strong>
      </span>
    </p>
    <p v-if="semLeitura" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.SEM_LEITURA`) }}
    </p>
  </div>
</template>
