<script setup>
import { nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import FunilEtapaLinha from './FunilEtapaLinha.vue';

// #1384 — a lista de etapas do funil: arrastar pela alça (ou setas do
// teclado nela) muda a ordem, e o leitor de tela ouve a posição nova.
defineProps({
  // Frase de uma etapa (a gaveta sabe onde ela mora).
  fraseDe: { type: Function, required: true },
  ia: { type: Boolean, default: false },
  travada: { type: Boolean, default: false },
});

defineEmits(['alterar', 'criar']);

const etapas = defineModel({ type: Array, required: true });

const { t } = useI18n();
const anuncio = ref('');
const alcas = ref({});

const anunciar = etapa => {
  anuncio.value = t('CRM_KANBAN.PIPELINE_EDITOR.ORDER_CHANGED', {
    name: etapa.name,
    position: etapas.value.indexOf(etapa) + 1,
    total: etapas.value.length,
  });
};

const mover = (de, direcao) => {
  const para = de + direcao;
  if (para < 0 || para >= etapas.value.length) return;
  const lista = [...etapas.value];
  const [etapa] = lista.splice(de, 1);
  const pelaAlca = alcas.value[etapa.editorKey] === document.activeElement;
  lista.splice(para, 0, etapa);
  etapas.value = lista;
  anunciar(etapa);
  if (pelaAlca) nextTick(() => alcas.value[etapa.editorKey]?.focus());
};
</script>

<template>
  <p class="sr-only" aria-live="polite">{{ anuncio }}</p>
  <Draggable
    v-model="etapas"
    item-key="editorKey"
    handle=".stage-drag-handle"
    :animation="150"
    ghost-class="opacity-40"
    class="flex flex-col gap-3"
    :disabled="travada"
    @change="anunciar($event.moved.element)"
  >
    <template #item="{ element: etapa, index }">
      <FunilEtapaLinha
        :nome="etapa.name"
        :cor="etapa.color"
        :numero="index + 1"
        :frase="fraseDe(etapa)"
        :ia="ia"
        @alterar="$emit('alterar', etapa)"
        @criar="$emit('criar', etapa)"
      >
        <template #alca>
          <button
            :ref="
              el => {
                alcas[etapa.editorKey] = el;
              }
            "
            type="button"
            class="stage-drag-handle -ms-2 grid size-11 shrink-0 cursor-grab touch-none place-items-center rounded-lg text-n-slate-10 active:cursor-grabbing focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :aria-label="
              t('CRM_KANBAN.PIPELINE_EDITOR.REORDER_STAGE', {
                name: etapa.name,
              })
            "
            :title="
              t('CRM_KANBAN.PIPELINE_EDITOR.REORDER_STAGE', {
                name: etapa.name,
              })
            "
            @keydown.up.prevent="mover(index, -1)"
            @keydown.down.prevent="mover(index, 1)"
          >
            <span class="i-lucide-grip-vertical size-5" aria-hidden="true" />
          </button>
        </template>
      </FunilEtapaLinha>
    </template>
  </Draggable>
</template>
