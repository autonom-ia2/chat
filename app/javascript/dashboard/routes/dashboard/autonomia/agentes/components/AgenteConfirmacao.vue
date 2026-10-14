<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AgenteBotao from './AgenteBotao.vue';

// #1181 — diálogo de confirmação do módulo. Usa o Dialog do produto (<dialog> nativo: prende o
// foco, fecha no Esc e devolve o foco a quem abriu), com os botões AA no slot do rodapé no lugar
// dos botões da marca. Cancelar vem primeiro; o principal pode ser de perigo (excluir, parar).
defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  confirmar: { type: String, required: true },
  // Rótulo do botão que fecha sem fazer nada (padrão "Cancelar"; ex.: "Continuar aqui").
  cancelar: { type: String, default: '' },
  perigo: { type: Boolean, default: true },
  carregando: { type: Boolean, default: false },
});

// 'fechada' avisa que o diálogo fechou por qualquer caminho (Cancelar, Esc ou depois de confirmar);
// quem usa só limpa o próprio estado, sem chamar fechar de novo.
const emit = defineEmits(['confirmar', 'fechada']);

const { t } = useI18n();
const dialogo = ref(null);

const abrir = () => dialogo.value?.open();
const fechar = () => dialogo.value?.close();

defineExpose({ abrir, fechar });
</script>

<template>
  <Dialog
    ref="dialogo"
    type="alert"
    width="md"
    :title="titulo"
    :description="texto"
    @close="emit('fechada')"
  >
    <template #footer>
      <div data-botoes class="flex flex-wrap justify-end gap-2">
        <AgenteBotao
          variante="contorno"
          :desabilitado="carregando"
          @click="fechar"
        >
          {{ cancelar || t('AGENTS.JORNADA.COMUM.CANCELAR') }}
        </AgenteBotao>
        <AgenteBotao
          :variante="perigo ? 'perigo' : 'primario'"
          :carregando="carregando"
          @click="emit('confirmar')"
        >
          {{ confirmar }}
        </AgenteBotao>
      </div>
    </template>
  </Dialog>
</template>
