<script setup>
import { ref, useId, watch } from 'vue';
import { seloDe } from '../utils/acharChance';

// #2692 — um grupo da lista (v4, T1; molde CampaignJourney/
// AudienceFoundSection.vue): título com a contagem, aberto ou fechado. Só o
// grupo "Pouca chance" tem o link "Tirar estas".
const props = defineProps({
  chave: { type: String, required: true },
  titulo: { type: String, required: true },
  comecaFechado: { type: Boolean, default: false },
  podeTirar: { type: Boolean, default: false },
});
const emit = defineEmits(['tirar']);

const aberto = ref(!props.comecaFechado);
// Na demonstração o estado do endereço decide que grupos abrem.
watch(
  () => props.comecaFechado,
  fechado => {
    aberto.value = !fechado;
  }
);
const listaId = useId();
// Rodada 3: "Ficam de fora" sem ponto, em tom apagado e mais separado.
const deFora = props.chave === 'fora';
const ponto = deFora ? '' : seloDe(props.chave).ponto;
</script>

<template>
  <section
    class="flex flex-col"
    :class="{ 'mt-6': deFora }"
    :data-grupo="chave"
  >
    <header
      class="flex items-center justify-between gap-3 pb-2 border-b border-n-weak"
    >
      <button
        type="button"
        class="flex items-center min-w-0 gap-2 text-start min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-expanded="aberto"
        :aria-controls="listaId"
        @click="aberto = !aberto"
      >
        <span
          class="transition-transform i-lucide-chevron-down size-5 shrink-0 text-n-slate-11"
          :class="{ '-rotate-90 rtl:rotate-90': !aberto }"
          aria-hidden="true"
        />
        <span
          v-if="ponto"
          class="size-2.5 shrink-0 rounded-full"
          :class="ponto"
        />
        <span
          class="text-base font-semibold"
          :class="deFora ? 'text-n-slate-11' : 'text-n-slate-12'"
        >
          {{ titulo }}
        </span>
      </button>
      <button
        v-if="podeTirar"
        type="button"
        class="px-3 text-sm font-medium min-h-11 shrink-0 rounded-xl text-n-blue-11 hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        data-tirar-estas
        @click="emit('tirar')"
      >
        {{ $t('PROSPECTING_ACHAR.CONFIRA.TIRAR_ESTAS') }}
      </button>
    </header>
    <ul
      v-show="aberto"
      :id="listaId"
      class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak"
    >
      <slot />
    </ul>
  </section>
</template>
