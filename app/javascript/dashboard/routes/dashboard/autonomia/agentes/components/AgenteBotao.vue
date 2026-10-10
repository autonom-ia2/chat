<script setup>
import { computed } from 'vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// #1181 (DECISOES.md item 10) — botão do módulo com contraste AA e alvo de toque de 44 px.
// Primário: azul 11 com texto branco no tema claro (4,9:1). No escuro o azul 11 fica claro, então o
// texto vira escuro (9:1); azul 10 com branco daria 4,48:1, abaixo do AA. Nunca a cor da marca com texto branco.
// Contorno: texto azul 11 (4,9:1 no claro) e borda azul 9 (3:1), como o .btn-outline do protótipo.
// Carregando: aria-disabled (não `disabled`), para o foco não cair no body, e o clique é ignorado.
const props = defineProps({
  variante: {
    type: String,
    default: 'primario',
    validator: v =>
      [
        'primario',
        'contorno',
        'fantasma',
        'branco',
        'perigo',
        'aviso',
      ].includes(v),
  },
  tamanho: {
    type: String,
    default: 'md',
    validator: v => ['md', 'lg', 'xl'].includes(v),
  },
  type: { type: String, default: 'button' },
  icone: { type: String, default: '' },
  iconeDireita: { type: String, default: '' },
  bloco: { type: Boolean, default: false },
  carregando: { type: Boolean, default: false },
  rotuloCarregando: { type: String, default: '' },
  desabilitado: { type: Boolean, default: false },
  // Inativo: continua focável e anunciado como indisponível (aria-disabled), mas não age.
  inativo: { type: Boolean, default: false },
});

const emit = defineEmits(['click']);

const VARIANTES = {
  primario:
    'bg-n-blue-11 text-white dark:text-n-slate-1 hover:brightness-110 focus-visible:outline-n-blue-11',
  perigo:
    'bg-n-ruby-11 text-white dark:text-n-slate-1 hover:brightness-110 focus-visible:outline-n-ruby-11',
  contorno:
    'bg-n-solid-1 text-n-blue-11 ring-1 ring-inset ring-n-blue-9 hover:bg-n-blue-2 focus-visible:outline-n-blue-11',
  fantasma:
    'bg-transparent text-n-blue-11 hover:bg-n-alpha-2 focus-visible:outline-n-blue-11',
  // Ação sem volta (protótipo .btn-warn): âmbar escuro #8A4F00 com branco, 6,6:1 nos dois temas.
  aviso:
    'bg-[#8A4F00] text-white hover:bg-[#723F00] dark:hover:bg-[#A35E00] focus-visible:outline-[#8A4F00]',
  branco:
    'bg-white text-[#0D2344] hover:bg-n-slate-2 focus-visible:outline-white',
};

const TAMANHOS = {
  md: 'min-h-11 px-4 text-sm',
  lg: 'min-h-12 px-5 text-base',
  xl: 'min-h-14 px-6 text-base',
};

const classes = computed(() => [
  'inline-flex items-center justify-center gap-2 font-semibold rounded-xl transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-50',
  VARIANTES[props.variante],
  TAMANHOS[props.tamanho],
  props.bloco ? 'w-full' : '',
  props.carregando ? 'cursor-wait' : '',
  props.inativo ? 'opacity-60 cursor-not-allowed' : '',
]);

const aoClicar = evento => {
  if (props.carregando || props.inativo || props.desabilitado) {
    evento.preventDefault();
    return;
  }
  emit('click', evento);
};
</script>

<template>
  <button
    :type="type"
    :class="classes"
    :disabled="desabilitado && !carregando"
    :aria-disabled="carregando || inativo ? 'true' : undefined"
    :aria-busy="carregando ? 'true' : undefined"
    @click="aoClicar"
  >
    <Spinner v-if="carregando" :size="16" aria-hidden="true" />
    <span v-else-if="icone" :class="icone" class="size-5" aria-hidden="true" />
    <span v-if="carregando && rotuloCarregando">{{ rotuloCarregando }}</span>
    <slot v-else />
    <span
      v-if="iconeDireita && !carregando"
      :class="iconeDireita"
      class="size-5 rtl:rotate-180"
      aria-hidden="true"
    />
  </button>
</template>
