<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import HeroiEscuro from 'dashboard/routes/dashboard/relacionamentos/components/comum/HeroiEscuro.vue';
import LinhaDoCupom from './LinhaDoCupom.vue';
import { F, useTextosDaFidelidade } from '../../useTextosDaFidelidade';

// #3100 — a aba Cupons: sem cupom, o herói com uma frase e "Criar cupom"; com
// cupons, o relatório de cada um (LinhaDoCupom) e "Novo cupom" no topo, para
// quem pode (`podeMudar`, fidelidade_manage); cada cupom repassa "Mandar este
// cupom", "Pausar" e "Ligar de novo". `cupons` nulo é carregando.
defineProps({
  cupons: { type: Array, default: null },
  podeMudar: { type: Boolean, default: false },
});
const emit = defineEmits(['criar', 'mandar', 'pausar', 'ligar']);

const { t } = useTextosDaFidelidade();
const C = `${F}.CUPONS`;
</script>

<template>
  <div data-fidelidade="cupons" class="flex flex-col gap-4">
    <div
      v-if="!cupons"
      data-fidelidade="carregando"
      aria-busy="true"
      class="grid gap-4 md:grid-cols-2"
    >
      <span
        v-for="n in 2"
        :key="n"
        class="h-56 rounded-2xl bg-n-alpha-2 animate-pulse"
      />
    </div>

    <HeroiEscuro v-else-if="!cupons.length" data-fidelidade="cupons-vazio">
      <template #frase>{{ t(`${C}.VAZIO_FRASE`) }}</template>
      <template #apoio>{{ t(`${C}.VAZIO_APOIO`) }}</template>
      <template v-if="podeMudar" #acao>
        <Button
          data-fidelidade="criar-cupom"
          size="lg"
          icon="i-lucide-plus"
          class="min-h-11"
          :label="t(`${C}.CRIAR`)"
          @click="emit('criar')"
        />
      </template>
    </HeroiEscuro>

    <template v-else>
      <header class="flex flex-wrap items-center justify-between gap-3">
        <h2 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
          {{ t(`${C}.TITULO`) }}
        </h2>
        <Button
          v-if="podeMudar"
          data-fidelidade="novo-cupom"
          variant="faded"
          icon="i-lucide-plus"
          class="min-h-11"
          :label="t(`${C}.NOVO`)"
          @click="emit('criar')"
        />
      </header>
      <p class="m-0 -mt-2 text-sm text-n-slate-11">{{ t(`${C}.REGUA`) }}</p>
      <div class="grid gap-4 md:grid-cols-2">
        <LinhaDoCupom
          v-for="cupom in cupons"
          :key="cupom.id"
          :cupom="cupom"
          :pode-mudar="podeMudar"
          @mandar="emit('mandar', cupom)"
          @pausar="emit('pausar', cupom)"
          @ligar="emit('ligar', cupom)"
        />
      </div>
    </template>
  </div>
</template>
