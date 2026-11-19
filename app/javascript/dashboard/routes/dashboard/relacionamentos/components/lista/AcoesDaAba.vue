<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import MenuMaisAcoes from './MenuMaisAcoes.vue';

// #3062 — as duas ações da aba Pessoas que a lista de contatos de hoje tinha
// no menu do topo: "Baixar planilha" (discreto) e "Nova pessoa" (o botão
// cheio). Ficam à vista, com nome, na linha das abas. Cada uma só aparece para
// quem pode (quem decide é a página). Os dois têm a altura dos campos (h-10) e
// 44 px de área de toque (o ::before). Sem nenhuma das duas, a página nem monta
// a peça.
// Depois do redesenho do #3057, no celular as duas moram num botão-menu com
// nome, "Ações ▾" (o padrão do "Renovações ▾"), ao lado das abas: duas linhas
// de botão grande antes dos grupos empurravam a lista para baixo. Com uma ação
// só, ela continua à vista, com nome, também no celular.
const props = defineProps({
  podeCriar: { type: Boolean, default: false },
  podeBaixar: { type: Boolean, default: false },
});
const emit = defineEmits(['criar', 'baixar']);

const { t } = useI18n();
const TOPO = 'RELACIONAMENTOS.LISTA.TOPO';

const duas = computed(() => props.podeCriar && props.podeBaixar);
const itensDoMenu = computed(() => [
  {
    id: 'criar',
    icone: 'i-lucide-user-plus',
    rotulo: t(`${TOPO}.NOVA_PESSOA`),
  },
  { id: 'baixar', icone: 'i-lucide-download', rotulo: t(`${TOPO}.BAIXAR`) },
]);
const AVISAR = {
  criar: () => emit('criar'),
  baixar: () => emit('baixar'),
};
const ALVO =
  "relative whitespace-nowrap before:absolute before:content-[''] before:inset-x-0 before:-inset-y-0.5";
</script>

<template>
  <div data-relacionamentos="acoes-da-aba" class="flex items-center gap-3">
    <div class="items-center gap-3" :class="duas ? 'hidden sm:flex' : 'flex'">
      <Button
        v-if="podeBaixar"
        slate
        faded
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
    <div v-if="duas" data-relacionamentos="acoes-no-celular" class="sm:hidden">
      <MenuMaisAcoes
        :texto="t(`${TOPO}.ACOES`)"
        :itens="itensDoMenu"
        para-baixo
        @escolher="AVISAR[$event]()"
      />
    </div>
  </div>
</template>
