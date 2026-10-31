<script setup>
import { nextTick, onBeforeUnmount, ref, watch } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import FunilHeroi from 'dashboard/routes/dashboard/crm/components/funil/FunilHeroi.vue';

// #2414 F0 — a casca das gavetas do CRM de hoje (Editar funil e o cartão):
// cabeçalho escuro do FunilHeroi, corpo cinza e "Fechar" no rodapé. Só existe
// no protótipo, para os painéis novos aparecerem onde a pessoa já os procura.
const props = defineProps({
  aberta: { type: Boolean, default: false },
  rotulo: { type: String, required: true },
  icone: { type: String, default: 'i-lucide-kanban' },
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  migalha: { type: String, default: '' },
});

const emit = defineEmits(['fechar']);

const caixa = ref(null);

const aoTeclar = evento => {
  if (evento.key === 'Escape') emit('fechar');
};

watch(
  () => props.aberta,
  aberta => {
    if (aberta) {
      document.addEventListener('keydown', aoTeclar);
      nextTick(() => caixa.value?.focus());
    } else {
      document.removeEventListener('keydown', aoTeclar);
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => document.removeEventListener('keydown', aoTeclar));
</script>

<template>
  <Teleport to="body">
    <div v-if="aberta" class="fixed inset-0 z-50 flex justify-end">
      <div
        class="absolute inset-0 bg-n-alpha-black1"
        aria-hidden="true"
        @click="emit('fechar')"
      />
      <section
        ref="caixa"
        role="dialog"
        aria-modal="true"
        :aria-label="titulo"
        tabindex="-1"
        data-livre-gaveta
        class="relative flex h-full w-full flex-col bg-n-background shadow-2xl outline-none md:w-[calc(100vw-10rem)]"
      >
        <FunilHeroi
          :rotulo="rotulo"
          :icone="icone"
          :titulo="titulo"
          :texto="texto"
          :migalha="migalha"
          @fechar="emit('fechar')"
        />
        <div class="flex-1 overflow-y-auto">
          <slot />
        </div>
        <footer
          class="flex justify-end px-5 py-3 border-t shrink-0 border-n-weak bg-n-solid-1 sm:px-8"
        >
          <Button
            :label="$t('CRM_FUNIL.FECHAR')"
            slate
            faded
            class="min-h-11 min-w-32"
            @click="emit('fechar')"
          />
        </footer>
      </section>
    </div>
  </Teleport>
</template>
