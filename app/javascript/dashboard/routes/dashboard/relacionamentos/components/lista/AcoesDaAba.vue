<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #3062 — as duas ações da aba Pessoas que a lista de contatos de hoje tinha
// no menu do topo: "Baixar planilha" (discreto) e "Nova pessoa" (o botão
// cheio). Ficam à vista, com nome, na linha das abas. Cada uma só aparece para
// quem pode (quem decide é a página). Os dois têm a altura dos campos (h-10) e
// 44 px de área de toque (o ::before). Sem nenhuma das duas, a página nem monta
// a peça.
// No celular "Nova pessoa" continua um botão à vista (a página o põe acima das
// abas) e "Baixar planilha" sai daqui: vira a última linha da lista ("Baixar
// esta lista em planilha"), onde quem acabou de ver a lista procura.
defineProps({
  podeCriar: { type: Boolean, default: false },
  podeBaixar: { type: Boolean, default: false },
});
const emit = defineEmits(['criar', 'baixar']);

const { t } = useI18n();
const TOPO = 'RELACIONAMENTOS.LISTA.TOPO';
const ALVO =
  "relative whitespace-nowrap before:absolute before:content-[''] before:inset-x-0 before:-inset-y-0.5";
</script>

<template>
  <div data-relacionamentos="acoes-da-aba" class="flex items-center gap-3">
    <Button
      v-if="podeBaixar"
      slate
      faded
      class="hidden sm:inline-flex"
      :class="ALVO"
      icon="i-lucide-download"
      data-relacionamentos="baixar-planilha"
      aria-haspopup="dialog"
      :label="t(`${TOPO}.BAIXAR`)"
      @click="emit('baixar')"
    />
    <Button
      v-if="podeCriar"
      :class="ALVO"
      icon="i-lucide-user-plus"
      data-relacionamentos="nova-pessoa"
      aria-haspopup="dialog"
      :label="t(`${TOPO}.NOVA_PESSOA`)"
      @click="emit('criar')"
    />
  </div>
</template>
