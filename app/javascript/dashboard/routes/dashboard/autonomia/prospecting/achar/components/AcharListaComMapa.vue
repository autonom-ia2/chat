<script setup>
import { ref, watch } from 'vue';
import { useMediaQuery } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import AcharCortes from './AcharCortes.vue';
import AcharMapaDaLista from './AcharMapaDaLista.vue';

// #2692 — a lista com o mapa de apoio (pedido do Rodrigo depois da r5). A
// lista continua sendo a tela; o mapa não tem botão principal.
// - 1440 (xl): coluna à direita, fixa ao rolar.
// - 390: "Ver no mapa" ao lado de "Só com WhatsApp" abre o mapa em tela cheia,
//   com "Voltar para a lista". O rodapé da página ("Continuar") fica por cima
//   (z-10), então o mapa para atrás dele.
// O mapa só é montado onde aparece: no celular o script do Google nem carrega
// enquanto a pessoa não pede o mapa.
defineProps({
  empresas: { type: Array, required: true },
  primeiroId: { type: [Number, String], default: null },
  naoVai: { type: Set, required: true },
  comWhatsapp: { type: Boolean, default: true },
  comNome: { type: Boolean, default: false },
});
const soWhatsapp = defineModel('soWhatsapp', { type: Boolean, default: false });
const procuraNome = defineModel('procuraNome', { type: String, default: '' });
const destacada = defineModel('destacada', {
  type: [Number, String],
  default: null,
});

const NS = 'PROSPECTING_ACHAR.CONFIRA.MAPA';
const aoLado = useMediaQuery('(min-width: 1280px)');
const noMapa = ref(false);

const selecionar = id => {
  destacada.value = id;
  noMapa.value = false;
};

watch(aoLado, largo => {
  if (largo) noMapa.value = false;
});
</script>

<template>
  <div
    class="flex flex-col gap-6 xl:grid xl:grid-cols-[minmax(0,1fr)_20rem] xl:items-start xl:gap-8"
  >
    <div class="flex flex-col min-w-0 gap-6">
      <AcharCortes
        v-model:so-whatsapp="soWhatsapp"
        v-model:procura-nome="procuraNome"
        :com-whatsapp="comWhatsapp"
        :com-nome="comNome"
        :com-mapa="!aoLado"
        @ver-mapa="noMapa = true"
      />
      <slot />
    </div>

    <aside
      v-if="aoLado"
      class="sticky top-6"
      :aria-label="$t(`${NS}.ROTULO`)"
      data-mapa-ao-lado
    >
      <AcharMapaDaLista
        :destacada="destacada"
        :empresas="empresas"
        :primeiro-id="primeiroId"
        :nao-vai="naoVai"
        height-class="h-[calc(100dvh-12rem)] min-h-[20rem] !rounded-2xl"
        @selecionar="selecionar"
      />
    </aside>

    <div
      v-if="noMapa && !aoLado"
      class="fixed inset-0 z-[5] flex flex-col gap-3 px-4 pt-4 pb-24 bg-n-surface-1"
      role="dialog"
      :aria-label="$t(`${NS}.ROTULO`)"
      data-mapa-tela-cheia
    >
      <Button
        :label="$t(`${NS}.VOLTAR`)"
        icon="i-lucide-arrow-left"
        slate
        faded
        class="self-start !min-h-11"
        data-voltar-lista
        @click="noMapa = false"
      />
      <AcharMapaDaLista
        :destacada="destacada"
        :empresas="empresas"
        :primeiro-id="primeiroId"
        :nao-vai="naoVai"
        height-class="flex-1 !rounded-2xl"
        @selecionar="selecionar"
      />
    </div>
  </div>
</template>
