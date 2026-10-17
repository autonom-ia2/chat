<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Pílula flutuante "3 itens abaixo"/"2 itens acima" do menu novo (#1781). Fica por cima da lista (absolute),
// centrada, a ~10 px da borda; área de toque de 44 px. Recolhido, mostra só o chevron.
const props = defineProps({
  lado: { type: String, required: true },
  visivel: { type: Boolean, default: false },
  contagem: { type: Number, default: 0 },
  recolhido: { type: Boolean, default: false },
  respirando: { type: Boolean, default: false },
  controla: { type: String, required: true },
  tema: { type: Object, required: true },
});

const emit = defineEmits(['rolar']);

const { t } = useI18n();
const emCima = computed(() => props.lado === 'acima');

const texto = computed(() => {
  if (!props.contagem) {
    return t(
      emCima.value ? 'FORK_SIDEBAR.MAIS_ACIMA' : 'FORK_SIDEBAR.MAIS_ABAIXO'
    );
  }
  const chave = emCima.value
    ? 'FORK_SIDEBAR.ITENS_ACIMA'
    : 'FORK_SIDEBAR.ITENS_ABAIXO';
  return t(chave, { count: props.contagem }, props.contagem);
});

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
      class="group absolute inset-x-0 z-[2] flex items-center justify-center mx-auto w-fit min-h-11 min-w-11 rounded-full"
      :class="[tema.foco, emCima ? 'top-1.5' : 'bottom-1.5']"
      @click="emit('rolar')"
    >
      <span
        class="flex items-center gap-1 h-8 rounded-full text-xs font-semibold transition duration-200 motion-reduce:transition-none"
        :class="[
          tema.pilula,
          tema.pilulaPassar,
          recolhido ? 'w-8 justify-center' : 'px-3',
        ]"
      >
        <span
          class="size-4 shrink-0 transition-transform duration-300 ease-in-out motion-reduce:transition-none"
          :class="[
            emCima ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down',
            deslocamento,
          ]"
          aria-hidden="true"
        />
        <span v-if="!recolhido" aria-hidden="true">{{ texto }}</span>
      </span>
    </button>
  </Transition>
</template>
