<script setup>
import { computed } from 'vue';

// #1149 — onde a pessoa está: Chega → Quem cuida → Sozinho → Confira. Etapa
// anterior ganha o visto; toda etapa já alcançada abre com um clique (caixa já
// no CRM abre todas, para ir direto ao que mudar).
const props = defineProps({
  atual: { type: Number, required: true },
  // Última etapa que a pessoa já pode abrir.
  alcancada: { type: Number, required: true },
});

defineEmits(['ir']);

const ETAPAS = ['CHEGA', 'CUIDAM', 'SOZINHO', 'CONFIRA'];

const etapas = computed(() =>
  ETAPAS.map((chave, indice) => {
    const numero = indice + 1;
    return {
      chave,
      numero,
      agora: numero === props.atual,
      feita: numero < props.atual,
      aberta: numero <= props.alcancada,
    };
  })
);
</script>

<template>
  <ol
    :aria-label="$t('CRM_CAIXAS.ETAPAS.ROTULO')"
    class="m-0 flex list-none flex-wrap items-center gap-x-2 gap-y-2 p-0"
  >
    <template v-for="(etapa, indice) in etapas" :key="etapa.chave">
      <li
        v-if="indice > 0"
        aria-hidden="true"
        class="hidden h-0.5 w-6 rounded-full sm:block"
        :class="etapa.aberta ? 'bg-n-blue-7' : 'bg-n-slate-6'"
      />
      <li>
        <button
          type="button"
          :data-etapa="etapa.chave"
          :aria-current="etapa.agora ? 'step' : undefined"
          :disabled="!etapa.aberta"
          class="flex min-h-11 items-center gap-2 rounded-xl px-2 text-[0.9375rem] font-semibold disabled:cursor-default enabled:hover:bg-n-alpha-2"
          :class="{
            'text-n-blue-11': etapa.agora,
            'text-n-teal-11': etapa.feita,
            'text-n-slate-10': !etapa.agora && !etapa.feita,
          }"
          @click="$emit('ir', etapa.numero)"
        >
          <span
            class="grid size-8 place-items-center rounded-full text-sm font-bold"
            :class="{
              'bg-n-blue-3': etapa.agora,
              'bg-n-teal-3': etapa.feita,
              'bg-n-slate-3': !etapa.agora && !etapa.feita,
            }"
          >
            <span
              v-if="etapa.feita"
              class="i-lucide-check size-4"
              aria-hidden="true"
            />
            <template v-else>{{ etapa.numero }}</template>
          </span>
          <span :class="etapa.agora ? '' : 'sr-only sm:not-sr-only'">
            {{ $t(`CRM_CAIXAS.ETAPAS.${etapa.chave}`) }}
          </span>
        </button>
      </li>
    </template>
  </ol>
</template>
