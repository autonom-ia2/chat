<script setup>
import { ref } from 'vue';
import { FALHA_DA_PARTE } from '../../ficha/falhas';
import CartaoDeInformacoes from './CartaoDeInformacoes.vue';
import DeOndeVeio from './DeOndeVeio.vue';
import SecaoArquivos from './SecaoArquivos.vue';
import SecaoCards from './SecaoCards.vue';
import SecaoConversas from './SecaoConversas.vue';
import SecaoNotas from './SecaoNotas.vue';

// #2894 — o corpo da ficha da pessoa. Duas colunas independentes: a principal
// (Conversas, Cards, Notas, Arquivos) e a do lado (Informações, De onde veio).
// Cada cartão tem o tamanho do próprio conteúdo: não há linha compartilhada entre
// as colunas, então nenhum vão nasce da altura do vizinho. No celular uma coluna
// vem depois da outra, na mesma ordem do documento: o que se vê é o que o Tab e o
// leitor de tela percorrem. A parte que quem está olhando não pode ver some; a
// que não carregou fica, com "Tentar de novo" (`falhas`, ficha/falhas.js). Quem
// só pode ver o contato (`podeEditar` falso) não tem "Alterar" nem a caixa de
// nota. #3071 — com `podeAbrirConversas`, cada conversa abre (`abrirConversa`)
// e "Ver todas" mostra todas ali mesmo; sem ele (a demonstração), "Ver todas"
// só avisa (`verTodas`). Apagar uma nota emite `apagarNota` com ela.
// #2897 — o slot `antes` abre a coluna principal: é onde a ficha põe o bloco
// Seguros (o que a pessoa tem com a corretora vem antes da conversa).
// #3075 — quem só pode ver lê em Informações que não pode mudar nada (a ficha
// antiga dizia o mesmo, RecordReadOnly). Quem pode mudar os campos da ficha
// (`podeEscolherCampos`) tem "Escolher campos" embaixo das informações. O slot
// `lado` vem depois de Informações: é onde a ficha põe "Este contato é".
const props = defineProps({
  conversas: { type: Array, required: true },
  cards: { type: Array, required: true },
  notas: { type: Array, required: true },
  arquivos: { type: Array, required: true },
  origem: { type: Object, default: null },
  linhas: { type: Array, required: true },
  redes: { type: Array, required: true },
  agora: { type: Number, required: true },
  guardandoNota: { type: Boolean, default: false },
  falhas: { type: Object, default: () => ({}) },
  podeEditar: { type: Boolean, default: true },
  podeVerTodas: { type: Boolean, default: false },
  podeAbrirConversas: { type: Boolean, default: false },
  podeEscolherCampos: { type: Boolean, default: false },
});
const emit = defineEmits([
  'verTodas',
  'abrirCard',
  'guardarNota',
  'alterar',
  'tentar',
  'abrirConversa',
  'apagarNota',
  'escolherCampos',
]);

const podeVer = parte => props.falhas[parte] !== FALHA_DA_PARTE.SEM_ACESSO;
const falhou = parte => props.falhas[parte] === FALHA_DA_PARTE.ERRO;

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
      <slot name="antes" />
      <SecaoConversas
        v-if="podeVer('conversas')"
        :conversas="conversas"
        :agora="agora"
        :falhou="falhou('conversas')"
        :pode-ver-todas="podeVerTodas"
        :pode-abrir="podeAbrirConversas"
        @ver-todas="emit('verTodas')"
        @abrir="conversaId => emit('abrirConversa', conversaId)"
        @tentar="emit('tentar', 'conversas')"
      />
      <SecaoCards
        v-if="podeVer('cards')"
        :cards="cards"
        :falhou="falhou('cards')"
        @abrir="card => emit('abrirCard', card)"
        @tentar="emit('tentar', 'cards')"
      />
      <SecaoNotas
        v-if="podeVer('notas')"
        ref="caixaDeNotas"
        :notas="notas"
        :guardando="guardandoNota"
        :agora="agora"
        :pode-escrever="podeEditar"
        :falhou="falhou('notas')"
        @guardar="texto => emit('guardarNota', texto)"
        @apagar="nota => emit('apagarNota', nota)"
        @tentar="emit('tentar', 'notas')"
      />
      <SecaoArquivos
        v-if="podeVer('arquivos')"
        :arquivos="arquivos"
        :agora="agora"
        :falhou="falhou('arquivos')"
        @tentar="emit('tentar', 'arquivos')"
      />
    </div>
    <div data-relacionamentos="coluna-lado" class="flex flex-col min-w-0 gap-6">
      <CartaoDeInformacoes
        :linhas="linhas"
        :redes="redes"
        :pode-editar="podeEditar"
        :pode-escolher-campos="podeEscolherCampos"
        @alterar="emit('alterar')"
        @escolher-campos="emit('escolherCampos')"
      />
      <slot name="lado" />
      <DeOndeVeio
        v-if="podeVer('origem')"
        :origem="origem"
        :agora="agora"
        :falhou="falhou('origem')"
        @tentar="emit('tentar', 'origem')"
      />
    </div>
  </div>
</template>
