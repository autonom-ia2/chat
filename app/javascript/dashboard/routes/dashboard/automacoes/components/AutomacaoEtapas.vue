<script setup>
import { computed } from 'vue';

// #982 — onde a pessoa está: Conte (ainda sem automação) → Confira (montada,
// desligada) → Ligue (ligada). Etapa feita ganha o visto.
const props = defineProps({
  // 1, 2 ou 3; com 3 e `concluida`, as três aparecem feitas.
  atual: { type: Number, required: true },
  concluida: { type: Boolean, default: false },
});

const ETAPAS = ['CONTE', 'CONFIRA', 'LIGUE'];

const etapas = computed(() =>
  ETAPAS.map((chave, indice) => {
    const numero = indice + 1;
    const feita =
      numero < props.atual || (props.concluida && numero === props.atual);
    return { chave, numero, feita, agora: !feita && numero === props.atual };
  })
);
</script>

<template>
  <ol
    data-etapas
    :aria-label="$t('AUTOMACOES.ETAPAS.ROTULO')"
    class="flex flex-wrap items-center gap-3 p-0 m-0 list-none"
  >
    <template v-for="(etapa, indice) in etapas" :key="etapa.chave">
      <li
        v-if="indice > 0"
        aria-hidden="true"
        class="w-7 h-0.5 rounded-full"
        :class="etapa.feita || etapa.agora ? 'bg-n-blue-7' : 'bg-n-slate-6'"
      />
      <li
        :data-etapa="etapa.chave"
        :aria-current="etapa.agora ? 'step' : undefined"
        class="flex items-center gap-2.5 text-[0.9375rem] font-semibold"
        :class="{
          'text-n-teal-11': etapa.feita,
          'text-n-blue-11': etapa.agora,
          'text-n-slate-10': !etapa.feita && !etapa.agora,
        }"
      >
        <span
          class="grid text-sm font-bold rounded-full place-items-center size-8"
          :class="{
            'bg-n-teal-3': etapa.feita,
            'bg-n-blue-3': etapa.agora,
            'bg-n-slate-3': !etapa.feita && !etapa.agora,
          }"
        >
          <span
            v-if="etapa.feita"
            class="i-lucide-check size-4"
            aria-hidden="true"
          />
          <template v-else>{{ etapa.numero }}</template>
        </span>
        {{ $t(`AUTOMACOES.ETAPAS.${etapa.chave}`) }}
      </li>
    </template>
  </ol>
</template>
