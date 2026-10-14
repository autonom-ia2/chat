<script setup>
import { computed, ref, watch } from 'vue';

// #1181 (protótipo T02, stateAvatar) — avatar do cartão com a cor do estado: quem está atendendo
// tem círculo verde-água sólido com a inicial em branco; parado, cotação e rascunho ficam neutros.
// Nasce no módulo porque o Avatar compartilhado escolhe a cor pelo nome e não pode ser editado
// (construção aditiva). Com foto, a foto aparece (em cinza quando neutro); se ela não carregar,
// volta a inicial. Decorativo: o nome já está no título do cartão.
const props = defineProps({
  nome: { type: String, required: true },
  src: { type: String, default: '' },
  tom: {
    type: String,
    default: 'neutro',
    validator: v => ['atendendo', 'neutro'].includes(v),
  },
});

const fotoFalhou = ref(false);
watch(
  () => props.src,
  () => {
    fotoFalhou.value = false;
  }
);

const inicial = computed(() =>
  (props.nome || '?').trim().charAt(0).toUpperCase()
);
const atendendo = computed(() => props.tom === 'atendendo');
const comFoto = computed(() => Boolean(props.src) && !fotoFalhou.value);
</script>

<template>
  <span
    data-avatar
    :data-tom="tom"
    aria-hidden="true"
    class="grid overflow-hidden text-lg font-bold rounded-full place-items-center size-12 shrink-0"
    :class="
      atendendo ? 'bg-[#00705F] text-white' : 'bg-n-slate-3 text-n-slate-11'
    "
  >
    <img
      v-if="comFoto"
      :src="src"
      alt=""
      class="object-cover size-full"
      :class="atendendo ? '' : 'grayscale'"
      @error="fotoFalhou = true"
    />
    <template v-else>{{ inicial }}</template>
  </span>
</template>
