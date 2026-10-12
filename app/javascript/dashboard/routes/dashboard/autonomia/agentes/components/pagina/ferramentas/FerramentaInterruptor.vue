<script setup>
import { computed } from 'vue';

// #1301 (protótipo F01/F09) — interruptor Ligada/Desligada sobre fundo claro. role=switch, alvo de
// 44 px e o estado escrito ao lado. O nome acessível diz o que ele controla ("Usar … no
// atendimento"); o estado vai em aria-checked. Quem usa decide o que acontece (desligar pede
// confirmação; ligar passa pelo teste), por isso ele só emite o valor pedido.
// Trilho: teal 10 ligado e slate 9 desligado, os dois com 3:1 ou mais contra o fundo.
const props = defineProps({
  ligado: { type: Boolean, required: true },
  rotulo: { type: String, required: true },
  textoLigado: { type: String, default: '' },
  textoDesligado: { type: String, default: '' },
});

const emit = defineEmits(['alternar']);

const alternar = () => emit('alternar', !props.ligado);

// O nome acessível contém o texto visível (WCAG 2.5.3): "Usar … no atendimento: Ligada".
const estadoVisivel = computed(() =>
  props.ligado ? props.textoLigado : props.textoDesligado
);
const nomeAcessivel = computed(() =>
  estadoVisivel.value ? `${props.rotulo}: ${estadoVisivel.value}` : props.rotulo
);
</script>

<template>
  <button
    type="button"
    role="switch"
    :aria-checked="ligado ? 'true' : 'false'"
    :aria-label="nomeAcessivel"
    class="inline-flex items-center gap-2 px-1 text-sm font-medium rounded-xl min-h-11 shrink-0 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
    @click="alternar"
  >
    <span
      aria-hidden="true"
      class="relative inline-flex items-center h-6 transition rounded-full w-11 shrink-0"
      :class="ligado ? 'bg-n-teal-10' : 'bg-n-slate-9'"
    >
      <span
        class="absolute bg-white rounded-full shadow size-5 transition-all"
        :class="ligado ? 'start-[1.375rem]' : 'start-0.5'"
      />
    </span>
    <span v-if="textoLigado" aria-hidden="true" class="min-w-[4.5rem]">
      {{ estadoVisivel }}
    </span>
  </button>
</template>
