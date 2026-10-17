<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Seta flutuante do menu novo (#1781): só o chevron, sem fundo nem contorno, centrada a ~10 px da borda sobre o
// esmaecido. O toque é um círculo invisível de 44 px; o leitor de tela ouve quantos itens estão fora da vista.
const props = defineProps({
  lado: { type: String, required: true },
  visivel: { type: Boolean, default: false },
  contagem: { type: Number, default: 0 },
  respirando: { type: Boolean, default: false },
  controla: { type: String, required: true },
  tema: { type: Object, required: true },
});

const emit = defineEmits(['rolar']);

const { t } = useI18n();
const emCima = computed(() => props.lado === 'acima');

const rotulo = computed(() => {
  if (!props.contagem) {
    return t(
      emCima.value ? 'FORK_SIDEBAR.ROLAR_ACIMA' : 'FORK_SIDEBAR.ROLAR_ABAIXO'
    );
  }
  const chave = emCima.value
    ? 'FORK_SIDEBAR.ROLAR_ACIMA_ITENS'
    : 'FORK_SIDEBAR.ROLAR_ABAIXO_ITENS';
  return t(chave, { count: props.contagem }, props.contagem);
});

// O chevron desce (ou sobe) 2 px no respiro.
const deslocamento = computed(() => {
  if (!props.respirando) return 'translate-y-0';
  return emCima.value ? '-translate-y-0.5' : 'translate-y-0.5';
});
</script>

<template>
  <Transition
    enter-active-class="transition duration-200 ease-out motion-reduce:transition-none"
    leave-active-class="transition duration-200 ease-in motion-reduce:transition-none"
    :enter-from-class="`opacity-0 ${emCima ? '-translate-y-1' : 'translate-y-1'}`"
    :leave-to-class="`opacity-0 ${emCima ? '-translate-y-1' : 'translate-y-1'}`"
  >
    <button
      v-if="visivel"
      type="button"
      :data-seta="lado"
      :aria-label="rotulo"
      :aria-controls="controla"
      class="group absolute inset-x-0 z-[2] flex items-center justify-center mx-auto size-11 rounded-full"
      :class="[tema.foco, emCima ? 'top-0' : 'bottom-0']"
      @click="emit('rolar')"
    >
      <span
        class="size-6 transition duration-300 ease-in-out motion-reduce:transition-none"
        :class="[
          emCima ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down',
          tema.seta,
          tema.setaPassar,
          deslocamento,
        ]"
        aria-hidden="true"
      />
    </button>
  </Transition>
</template>
