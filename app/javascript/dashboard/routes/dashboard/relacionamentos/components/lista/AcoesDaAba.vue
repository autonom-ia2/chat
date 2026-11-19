<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #3062 — as duas ações da aba Pessoas que a lista de contatos de hoje tinha
// no menu do topo: "Baixar planilha" (discreto) e "Nova pessoa" (o botão
// cheio). Ficam à vista, com nome, ao lado das abas; no celular dividem a
// linha. Cada uma só aparece para quem pode (quem decide é a página). Os dois
// têm a altura dos campos (h-10) e 44 px de área de toque (o ::before). Sem
// nenhuma das duas, a página nem monta a peça.
defineProps({
  podeCriar: { type: Boolean, default: false },
  podeBaixar: { type: Boolean, default: false },
});
const emit = defineEmits(['criar', 'baixar']);

const { t } = useI18n();
</script>

<template>
  <div
    data-relacionamentos="acoes-da-aba"
    class="flex items-center w-full gap-3 sm:w-auto"
  >
    <Button
      v-if="podeBaixar"
      slate
      faded
      class="relative flex-1 whitespace-nowrap sm:flex-none before:absolute before:content-[''] before:inset-x-0 before:-inset-y-0.5"
      icon="i-lucide-download"
      data-relacionamentos="baixar-planilha"
      aria-haspopup="dialog"
      :label="t('RELACIONAMENTOS.LISTA.TOPO.BAIXAR')"
      @click="emit('baixar')"
    />
    <Button
      v-if="podeCriar"
      class="relative flex-1 whitespace-nowrap sm:flex-none before:absolute before:content-[''] before:inset-x-0 before:-inset-y-0.5"
      icon="i-lucide-user-plus"
      data-relacionamentos="nova-pessoa"
      aria-haspopup="dialog"
      :label="t('RELACIONAMENTOS.LISTA.TOPO.NOVA_PESSOA')"
      @click="emit('criar')"
    />
  </div>
</template>
