<script setup>
import { computed } from 'vue';

// Contagem do menu novo (#1617): o mesmo desenho do SidebarUnreadBadge, com as cores do visual (padrão ou marca).
const props = defineProps({
  numero: { type: [Number, String], default: 0 },
  classes: { type: String, default: '' },
});

const valor = computed(() => {
  const numero = Number(props.numero);
  return Number.isFinite(numero) && numero > 0 ? numero : 0;
});
const texto = computed(() => (valor.value > 99 ? '99+' : String(valor.value)));
</script>

<template>
  <span
    v-if="valor > 0"
    data-contador
    class="inline-grid h-5 min-w-5 shrink-0 place-items-center rounded-full px-1.5 text-xs font-semibold leading-none tabular-nums"
    :class="classes"
  >
    {{ texto }}
  </span>
  <template v-else />
</template>
