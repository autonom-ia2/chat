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

// #2894 — o corpo da ficha da pessoa. Duas colunas independentes: a principal
// (Conversas, Cards, Notas, Arquivos) e a do lado (Informações, De onde veio).
// Cada cartão tem o tamanho do próprio conteúdo: não há linha compartilhada entre
// as colunas, então nenhum vão nasce da altura do vizinho. No celular uma coluna
// vem depois da outra, na mesma ordem do documento: o que se vê é o que o Tab e o
// leitor de tela percorrem.
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
    class="flex flex-col min-w-0 gap-6 lg:grid lg:grid-cols-3 lg:items-start"
  >
    <div
      data-relacionamentos="coluna-principal"
      class="flex flex-col min-w-0 gap-6 lg:col-span-2"
    >
      <!-- #2897: o que a pessoa "tem comigo" vem antes da conversa. -->
      <slot name="antes" />
      <SecaoConversas
        :conversas="conversas"
        :agora="agora"
        @ver-todas="emit('verTodas')"
      />
      <SecaoCards :cards="cards" @abrir="card => emit('abrirCard', card)" />
      <SecaoNotas
        ref="caixaDeNotas"
        :notas="notas"
        :guardando="guardandoNota"
        :agora="agora"
        @guardar="texto => emit('guardarNota', texto)"
      />
      <SecaoArquivos :arquivos="arquivos" :agora="agora" />
    </div>
    <div data-relacionamentos="coluna-lado" class="flex flex-col min-w-0 gap-6">
      <CartaoDaSecao
        :titulo="t('RELACIONAMENTOS_FICHA.INFORMACOES.TITULO')"
        data-relacionamentos="informacoes"
      >
        <template #acao>
          <Button
            data-relacionamentos="alterar"
            slate
            faded
            :label="t('RELACIONAMENTOS_FICHA.INFORMACOES.ALTERAR')"
            @click="emit('alterar')"
          />
        </template>
        <ListaDeInformacoes :linhas="linhas" :redes="redes" />
      </CartaoDaSecao>
      <DeOndeVeio :origem="origem" :agora="agora" />
    </div>
  </div>
</template>
