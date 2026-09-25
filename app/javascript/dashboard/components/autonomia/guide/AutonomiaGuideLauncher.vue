<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { isFixedPanelOpen } from 'dashboard/composables/useFixedPanelState';
import { useGuiaDescoberta } from './useGuiaDescoberta';
import GuideDot from './GuideDot.vue';

// Botão flutuante do "Guia da Plataforma", SÓ NO CELULAR (md:hidden). No computador a
// entrada fica no pé da barra lateral (GuideSidebarEntry, #697): um botão flutuante no
// canto cobria paginação e a última linha das listas. No celular não há barra lateral
// fixa, então fica a bolinha azul de 44 px, sem balão (na tela pequena ele cobriria o
// conteúdo); o ponto avisa até a primeira abertura.
// #646 — a fixed panel (e.g. CrmCardDrawer) can share this same bottom-right corner;
// `isFixedPanelOpen` lifts the launcher above that panel's footer instead of letting
// it cover the footer's buttons.
const { guiaDisponivel, painelAberto, mostrarPonto, alternarGuia } =
  useGuiaDescoberta();

const showLauncher = computed(
  () => guiaDisponivel.value && !painelAberto.value
);

const launcherRef = ref(null);

// O lançador some quando o painel abre e volta quando ele fecha, então
// `false → true` é exatamente "o painel acabou de fechar": é aí que o foco
// precisa voltar para cá, senão ele fica no nada e quem usa teclado recomeça
// do topo da página. O watcher não roda na montagem, então carregar a página
// com o painel fechado não rouba o foco de ninguém.
watch(showLauncher, async visivel => {
  if (!visivel) return;
  await nextTick();
  launcherRef.value?.$el?.focus();
});
</script>

<template>
  <div
    v-if="showLauncher"
    class="md:hidden fixed ltr:right-4 rtl:left-4 z-50 transition-[bottom] duration-200 ease-out"
    :class="isFixedPanelOpen ? 'bottom-24' : 'bottom-4'"
  >
    <div class="relative">
      <Button
        ref="launcherRef"
        data-guia-abrir
        icon="i-lucide-circle-help"
        :title="$t('AUTONOMIA_GUIDE.LAUNCHER_LABEL')"
        :aria-label="$t('AUTONOMIA_GUIDE.LAUNCHER_LABEL')"
        color="blue"
        no-animation
        class="!size-11 !rounded-full shadow-md hover:shadow-lg"
        @click="alternarGuia"
      />
      <GuideDot v-if="mostrarPonto" />
    </div>
  </div>
  <template v-else />
</template>
