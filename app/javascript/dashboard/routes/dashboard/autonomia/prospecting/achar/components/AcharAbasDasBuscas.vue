<script setup>
import { useAcharTela } from '../composables/useAcharTela';
import { ROTAS } from '../utils/acharRotas';

// #2775 — F6, as duas abas de "Suas buscas": as buscas e as listas guardadas.
// Só para quem pode guardar listas (a permissão do Guardar lista); para os
// outros, a página de buscas fica como era, sem abas.
const props = defineProps({
  atual: { type: String, required: true },
});

const NS = 'PROSPECTING_ACHAR.ABAS';
const { irPara } = useAcharTela();
const ABAS = [
  { id: 'buscas', chave: 'BUSCAS', rota: ROTAS.BUSCAS, estado: 'buscas' },
  { id: 'listas', chave: 'LISTAS', rota: ROTAS.LISTAS, estado: 'listas' },
];
const abrir = aba => {
  if (aba.id !== props.atual) irPara(aba.rota, { estado: aba.estado });
};
</script>

<template>
  <nav
    class="flex gap-2 p-1 rounded-2xl bg-n-slate-3 self-start"
    :aria-label="$t(`${NS}.ROTULO`)"
    data-abas
  >
    <button
      v-for="aba in ABAS"
      :key="aba.id"
      type="button"
      class="px-5 text-base font-medium min-h-11 rounded-xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :class="
        aba.id === atual
          ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
      :aria-current="aba.id === atual ? 'page' : undefined"
      :data-aba="aba.id"
      @click="abrir(aba)"
    >
      {{ $t(`${NS}.${aba.chave}`) }}
    </button>
  </nav>
</template>
