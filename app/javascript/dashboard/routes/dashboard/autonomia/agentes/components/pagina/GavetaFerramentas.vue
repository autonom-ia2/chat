<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteGaveta from '../AgenteGaveta.vue';
import PanelTools from '../../../components/panel/PanelTools.vue';

// #1181 piloto — "Ferramentas" (chamadas HTTP que o agente consulta) só para SuperAdmin, como a aba
// do painel antigo; o backend (Agents::ToolsController) também exige SuperAdmin. A gaveta só
// embrulha o PanelTools existente, sem mudá-lo, com as mesmas props que o painel antigo passava.
defineProps({
  agente: { type: Object, required: true },
});

const emit = defineEmits(['fechar']);

const { t } = useI18n();
const conteudo = ref(null);

// O formulário de criar/editar ferramenta do PanelTools é um `div fixed` com <form> (não um
// <dialog>), então o Esc da gaveta não o enxerga: com ele aberto, Esc ou clique no fundo fechariam
// a gaveta e perderiam o que foi digitado. Enquanto houver formulário, a gaveta não fecha.
const podeFechar = () => !conteudo.value?.querySelector('form');
</script>

<template>
  <AgenteGaveta
    larga
    :titulo="t('AGENTS.JORNADA.PAGINA.FERRAMENTAS.TITULO')"
    :pode-fechar="podeFechar"
    @fechar="emit('fechar')"
  >
    <div ref="conteudo" class="relative">
      <PanelTools data-ferramentas :agent-id="Number(agente.id)" />
    </div>
  </AgenteGaveta>
</template>
