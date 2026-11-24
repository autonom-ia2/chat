<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import { useGuiaDescoberta } from './useGuiaDescoberta';
import { useAvisosDoGuia } from './useAvisosDoGuia';
import GuideDot from './GuideDot.vue';

// #3192 — o Guia no cabeçalho da conversa, SÓ NO CELULAR (md:hidden). Na
// conversa aberta a bolinha flutuante some (AutonomiaGuideLauncher): ela ficava
// em cima do botão de enviar. Botão com o nome escrito, não só ícone: quem não
// é da área não adivinha o que um ícone faz. Azul claro, da família da bolinha:
// cinza ao lado do nome parecia coisa da cliente. O ponto e o contador de avisos
// novos vêm junto, como na bolinha. O botão tem 32 px, como os vizinhos (o
// cabeçalho tem altura fixa), e a área de toque passa de 44 px pela borda
// invisível, o mesmo jeito do PassarParaButton.
const { t } = useI18n();
const { guiaDisponivel, painelAberto, mostrarPonto, alternarGuia } =
  useGuiaDescoberta();
const { quantidade: avisosNovos, carregar: carregarAvisos } = useAvisosDoGuia();
const accountId = useMapGetter('getCurrentAccountId');
onMounted(carregarAvisos);
watch(accountId, carregarAvisos);

const rotulo = computed(() =>
  avisosNovos.value > 0
    ? t(
        'AUTONOMIA_GUIDE.AVISOS.LAUNCHER_LABEL',
        { count: avisosNovos.value },
        avisosNovos.value
      )
    : t('AUTONOMIA_GUIDE.LAUNCHER_LABEL')
);

const visivel = computed(() => guiaDisponivel.value && !painelAberto.value);

// O painel fecha e este botão volta: o foco volta para ele, senão quem usa
// teclado recomeça do topo da página. Segue o painel, não a visibilidade, para
// trocar de tela não roubar o foco.
const botao = ref(null);
watch(painelAberto, async (aberto, antes) => {
  if (aberto || !antes) return;
  await nextTick();
  if (visivel.value) botao.value?.$el?.focus();
});
</script>

<template>
  <div v-show="visivel" class="relative md:hidden shrink-0" data-guia-cabecalho>
    <Button
      ref="botao"
      :label="t('AUTONOMIA_GUIDE.HEADER.NAME')"
      :aria-label="rotulo"
      icon="i-lucide-circle-help"
      sm
      blue
      faded
      class="relative before:absolute before:-inset-1.5"
      @click="alternarGuia"
    />
    <GuideDot v-if="avisosNovos > 0 || mostrarPonto" :numero="avisosNovos" />
  </div>
</template>
