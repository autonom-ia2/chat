<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

// Dica do menu recolhido (#1617): etiqueta ao lado do ícone com o nome (e a contagem). Fica sempre no DOM para
// o aria-describedby do ícone apontar para ela; aparece quando `visivel`.
const props = defineProps({
  id: { type: String, required: true },
  texto: { type: String, required: true },
  visivel: { type: Boolean, default: false },
  retangulo: { type: Object, default: () => ({ top: 0, right: 0, left: 0 }) },
});

const DISTANCIA = 10;
const isRTL = useMapGetter('accounts/isRTL');
const posicao = computed(() => ({
  top: `${props.retangulo.top + (props.retangulo.bottom - props.retangulo.top) / 2}px`,
  ...(isRTL.value
    ? { right: `${window.innerWidth - props.retangulo.left + DISTANCIA}px` }
    : { left: `${props.retangulo.right + DISTANCIA}px` }),
}));
</script>

<template>
  <TeleportWithDirection>
    <span
      :id="id"
      role="tooltip"
      data-dica
      class="fixed z-[100] -translate-y-1/2 px-3 py-2 text-sm font-medium rounded-lg shadow-lg pointer-events-none whitespace-nowrap bg-n-slate-12 text-n-slate-1"
      :class="visivel ? 'opacity-100' : 'opacity-0 invisible'"
      :style="posicao"
    >
      {{ texto }}
    </span>
  </TeleportWithDirection>
</template>
