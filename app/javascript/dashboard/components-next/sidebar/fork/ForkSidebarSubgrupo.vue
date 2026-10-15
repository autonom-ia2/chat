<script setup>
import { computed, ref, watch } from 'vue';
import SidebarSortMenu from '../SidebarSortMenu.vue';
import ForkSidebarFolha from './ForkSidebarFolha.vue';

// Lista que cresce com a conta, dentro de Conversas (Pastas, Times, Canais, Etiquetas) e de Contatos (#1617).
// Nasce fechada para o menu não virar uma parede; abre sozinha quando a tela de um filho está aberta.
const props = defineProps({
  subgrupo: { type: Object, required: true },
  folhas: { type: Array, required: true },
  ativaNome: { type: String, default: '' },
  tema: { type: Object, required: true },
});

const emit = defineEmits(['navegou']);

const temAtiva = computed(() =>
  props.folhas.some(folha => folha.name === props.ativaNome)
);
const aberto = ref(temAtiva.value);
watch(temAtiva, valor => {
  if (valor) aberto.value = true;
});

const idDaLista = computed(
  () => `fork-sub-${props.subgrupo.name.split(' ').join('-')}`
);
</script>

<template>
  <li class="min-w-0">
    <div class="flex items-center min-w-0 gap-1 pe-1">
      <button
        type="button"
        class="flex items-center flex-1 min-w-0 gap-2.5 text-[0.9375rem] leading-5 rounded-lg min-h-11 ps-11 pe-2 transition-colors duration-150 motion-reduce:transition-none"
        :class="[tema.foco, tema.textoFilho, tema.passar]"
        :aria-expanded="aberto"
        :aria-controls="idDaLista"
        @click="aberto = !aberto"
      >
        <span class="flex-1 min-w-0 truncate text-start">
          {{ subgrupo.label }}
        </span>
        <span
          class="i-lucide-chevron-down size-4 shrink-0 transition-transform duration-150 motion-reduce:transition-none"
          :class="{ 'rotate-180': aberto }"
          aria-hidden="true"
        />
      </button>
      <SidebarSortMenu
        v-if="aberto && subgrupo.sortOptions?.length"
        :active-sort="subgrupo.activeSort"
        :options="subgrupo.sortOptions"
        :open-on-hover="false"
        @sort="subgrupo.onSortChange"
      />
    </div>
    <ul
      v-if="aberto"
      :id="idDaLista"
      class="grid m-0 p-0 list-none min-w-0 overflow-y-auto max-h-72 [scrollbar-width:thin]"
    >
      <ForkSidebarFolha
        v-for="folha in folhas"
        :key="folha.name"
        :folha="folha"
        :ativa="folha.name === ativaNome"
        :tema="tema"
        neta
        @navegou="emit('navegou')"
      />
    </ul>
  </li>
</template>
