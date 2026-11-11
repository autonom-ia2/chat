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
// `order-*`. Informações ocupa as duas primeiras linhas, ao lado de Conversas e
// Cards; De onde veio fica ao lado de Notas.
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
const emit = defineEmits([
  'conversar',
  'verTodas',
  'abrirCard',
  'novoCard',
  'guardarNota',
  'alterar',
]);

const { t } = useI18n();
const caixaDeNotas = ref(null);

// A tela chama depois de guardar a nota com sucesso.
defineExpose({ limpar: () => caixaDeNotas.value?.limpar() });
</script>

<template>
  <div class="flex flex-col min-w-0 gap-6 lg:grid lg:grid-cols-3">
    <SecaoConversas
      class="lg:col-span-2 lg:col-start-1 lg:row-start-1"
      :conversas="conversas"
      :agora="agora"
      @conversar="emit('conversar')"
      @ver-todas="emit('verTodas')"
    />
    <SecaoCards
      class="lg:col-span-2 lg:col-start-1 lg:row-start-2"
      :cards="cards"
      @abrir="card => emit('abrirCard', card)"
      @novo-card="emit('novoCard')"
    />
    <CartaoDaSecao
      class="lg:col-start-3 lg:row-start-1 lg:row-span-2"
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
      class="lg:col-span-2 lg:col-start-1 lg:row-start-3"
      :notas="notas"
      :guardando="guardandoNota"
      :agora="agora"
      @guardar="texto => emit('guardarNota', texto)"
    />
    <SecaoArquivos
      class="lg:col-span-2 lg:col-start-1 lg:row-start-4"
      :arquivos="arquivos"
      :agora="agora"
    />
    <DeOndeVeio
      class="lg:col-start-3 lg:row-start-3 lg:self-start"
      :origem="origem"
    />
  </div>
</template>
