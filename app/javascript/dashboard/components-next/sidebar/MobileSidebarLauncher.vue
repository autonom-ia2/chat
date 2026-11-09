<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import { useEscondeAoRolar } from './useEscondeAoRolar';
import { useTelaDeConversa } from './useTelaDeConversa';

const props = defineProps({
  isMobileSidebarOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle']);

const isConversationRoute = useTelaDeConversa();

// #2207 — some enquanto a página rola; com o menu aberto, fica. Só existe abaixo de md (md:hidden).
const launcher = ref(null);
const { rolando } = useEscondeAoRolar(launcher);
const escondido = computed(() => rolando.value && !props.isMobileSidebarOpen);

const toggleSidebar = () => {
  emit('toggle');
};
</script>

<template>
  <div
    v-if="!isConversationRoute"
    id="mobile-sidebar-launcher"
    ref="launcher"
    class="fixed bottom-4 ltr:left-4 rtl:right-4 z-40 transition duration-200 ease-out motion-reduce:transition-none block md:hidden focus-within:opacity-100 focus-within:translate-y-0 focus-within:pointer-events-auto"
    :class="[
      {
        'ltr:translate-x-48 rtl:-translate-x-48': isMobileSidebarOpen,
        'opacity-0 translate-y-4 pointer-events-none': escondido,
      },
    ]"
  >
    <ButtonGroup
      class="rounded-full bg-n-alpha-2 backdrop-blur-lg p-1 shadow hover:shadow-md"
    >
      <Button
        icon="i-lucide-menu"
        no-animation
        class="!rounded-full !bg-n-solid-3 dark:!bg-n-alpha-2 !text-n-slate-12 text-xl transition-all duration-200 ease-out hover:brightness-110"
        lg
        @click="toggleSidebar"
      />
    </ButtonGroup>
  </div>
  <template v-else />
</template>
