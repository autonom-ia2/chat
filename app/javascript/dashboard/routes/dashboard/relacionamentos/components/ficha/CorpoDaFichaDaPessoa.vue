<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CartaoDaSecao from './CartaoDaSecao.vue';
import DeOndeVeio from './DeOndeVeio.vue';
import ListaDeInformacoes from './ListaDeInformacoes.vue';
import SecaoArquivos from './SecaoArquivos.vue';
import SecaoCards from './SecaoCards.vue';
import SecaoConversas from './SecaoConversas.vue';
import SecaoNotas from './SecaoNotas.vue';

// #2894 — o corpo da ficha da pessoa. O DOM está na ordem do celular (e do Tab e
// do leitor de tela): Conversas, Cards, Informações, Notas, Arquivos, De onde
// veio. No desktop um grid com colunas e linhas explícitas põe as quatro seções
// principais nas colunas 1-2 e Informações e De onde veio na coluna 3, sem
// `order-*`. Informações atravessa as linhas 1 a 3, e a 3 é uma linha-folga
// (`1fr`, vazia): a altura extra de Informações cai nela, então Conversas e Cards
// ficam do tamanho do próprio conteúdo (seção vazia não estica). De onde veio
// começa na linha 4, ao lado de Notas. O espaço entre as seções no desktop vem de
// `mb-6` (não de `gap-y`), para a linha-folga não somar um vão a mais.
defineProps({
  conversas: { type: Array, required: true },
  cards: { type: Array, required: true },
  notas: { type: Array, required: true },
  arquivos: { type: Array, required: true },
  origem: { type: Object, default: null },
  linhas: { type: Array, required: true },
  redes: { type: Array, required: true },
  agora: { type: Number, required: true },
  guardandoNota: { type: Boolean, default: false },
});
const emit = defineEmits(['verTodas', 'abrirCard', 'guardarNota', 'alterar']);

const { t } = useI18n();
const caixaDeNotas = ref(null);

// A tela chama depois de guardar a nota com sucesso.
defineExpose({ limpar: () => caixaDeNotas.value?.limpar() });
</script>

<template>
  <div
    class="flex flex-col min-w-0 gap-6 lg:grid lg:grid-cols-3 lg:gap-y-0 lg:grid-rows-[auto_auto_1fr_auto_auto]"
  >
    <SecaoConversas
      class="lg:col-span-2 lg:col-start-1 lg:row-start-1 lg:mb-6"
      :conversas="conversas"
      :agora="agora"
      @ver-todas="emit('verTodas')"
    />
    <SecaoCards
      class="lg:col-span-2 lg:col-start-1 lg:row-start-2 lg:mb-6"
      :cards="cards"
      @abrir="card => emit('abrirCard', card)"
    />
    <CartaoDaSecao
      class="lg:col-start-3 lg:row-start-1 lg:row-span-3 lg:mb-6"
      :titulo="t('RELACIONAMENTOS_FICHA.INFORMACOES.TITULO')"
      data-relacionamentos="informacoes"
    >
      <template #acao>
        <Button
          data-relacionamentos="alterar"
          slate
          faded
          class="min-h-11"
          :label="t('RELACIONAMENTOS_FICHA.INFORMACOES.ALTERAR')"
          @click="emit('alterar')"
        />
      </template>
      <ListaDeInformacoes :linhas="linhas" :redes="redes" />
    </CartaoDaSecao>
    <SecaoNotas
      ref="caixaDeNotas"
      class="lg:col-span-2 lg:col-start-1 lg:row-start-4 lg:mb-6"
      :notas="notas"
      :guardando="guardandoNota"
      :agora="agora"
      @guardar="texto => emit('guardarNota', texto)"
    />
    <SecaoArquivos
      class="lg:col-span-2 lg:col-start-1 lg:row-start-5"
      :arquivos="arquivos"
      :agora="agora"
    />
    <DeOndeVeio
      class="lg:col-start-3 lg:row-start-4 lg:self-start"
      :origem="origem"
      :agora="agora"
    />
  </div>
</template>
