<script setup>
import { computed } from 'vue';

// #1384 — onde a pessoa está: ao criar, Nome → Etapas → Confira; no Google,
// Copie → Cole → Ligue. Mesmo desenho de CaixaEtapas: passo feito ganha o
// visto e volta com um toque; o passo de agora tem o número cheio; o próximo,
// cinza legível.
const props = defineProps({
  atual: { type: Number, required: true },
  // Chaves de i18n de cada passo, na ordem.
  nomes: {
    type: Array,
    default: () => [
      'CRM_FUNIL.PASSOS.NOME',
      'CRM_FUNIL.PASSOS.ETAPAS',
      'CRM_FUNIL.PASSOS.CONFIRA',
    ],
  },
  rotulo: { type: String, default: 'CRM_FUNIL.PASSOS.ROTULO' },
});

defineEmits(['ir']);

const passos = computed(() =>
  props.nomes.map((chave, indice) => {
    const numero = indice + 1;
    return {
      chave,
      numero,
      agora: numero === props.atual,
      feito: numero < props.atual,
    };
  })
);
</script>

<template>
  <ol
    data-funil-passos
    :aria-label="$t(rotulo)"
    class="m-0 flex list-none flex-wrap items-center gap-1 p-0 sm:gap-2"
  >
    <template v-for="(passo, indice) in passos" :key="passo.chave">
      <li
        v-if="indice > 0"
        aria-hidden="true"
        class="h-0.5 w-4 rounded-full sm:w-8"
        :class="passo.agora || passo.feito ? 'bg-n-blue-8' : 'bg-n-slate-6'"
      />
      <li>
        <component
          :is="passo.feito ? 'button' : 'span'"
          :type="passo.feito ? 'button' : undefined"
          :data-passo="passo.chave"
          :aria-current="passo.agora ? 'step' : undefined"
          class="flex min-h-11 items-center gap-1.5 rounded-xl px-1 text-[0.9375rem] font-semibold sm:gap-2 sm:px-2"
          :class="{
            'text-n-slate-12': passo.agora,
            'text-n-teal-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand':
              passo.feito,
            'text-n-slate-11': !passo.agora && !passo.feito,
          }"
          @click="passo.feito && $emit('ir', passo.numero)"
        >
          <span
            class="grid size-8 place-items-center rounded-full text-sm font-bold"
            :class="{
              'bg-n-blue-9 text-white': passo.agora,
              'bg-n-teal-3 text-n-teal-11': passo.feito,
              'bg-n-slate-3 text-n-slate-11': !passo.agora && !passo.feito,
            }"
          >
            <span
              v-if="passo.feito"
              class="i-lucide-check size-4"
              aria-hidden="true"
            />
            <template v-else>{{ passo.numero }}</template>
          </span>
          {{ $t(passo.chave) }}
        </component>
      </li>
    </template>
  </ol>
</template>
