<script setup>
import { useI18n } from 'vue-i18n';
import { FALHA_DA_PARTE } from '../../ficha/falhas';
import CartaoDeInformacoes from './CartaoDeInformacoes.vue';
import SecaoCards from './SecaoCards.vue';
import SecaoConversas from './SecaoConversas.vue';
import SecaoMidias from './SecaoMidias.vue';
import SecaoNotas from './SecaoNotas.vue';
import SecaoPessoasDaEmpresa from './SecaoPessoasDaEmpresa.vue';

// #3078 — o corpo da ficha da empresa, com as abas da ficha antiga de Empresas
// em blocos, no mesmo desenho da ficha da pessoa (CorpoDaFichaDaPessoa): na
// coluna principal Pessoas (pôr e tirar), o slot `depoisDasPessoas` (onde a
// ficha põe Seguros), Conversas (o histórico, cada uma abre), Cards, Notas (as
// das pessoas, só para ler) e Mídias (só com `comMidias`); do lado,
// Informações. No celular uma coluna vem depois da outra, na ordem do
// documento. A parte que quem está olhando não pode ver some; a que não
// carregou fica, com "Tentar de novo" (`falhas`, ficha/falhas.js).
// O que ainda só simula (conversar com uma pessoa daqui, "Ver todas" as
// conversas sem abrir) só existe na demonstração: `podeConversar`,
// `podeVerTodas`.
const props = defineProps({
  pessoas: { type: Array, required: true },
  totalDePessoas: { type: Number, default: 0 },
  conversas: { type: Array, required: true },
  cards: { type: Array, required: true },
  notas: { type: Array, required: true },
  midias: { type: Object, required: true },
  linhas: { type: Array, required: true },
  agora: { type: Number, required: true },
  falhas: { type: Object, default: () => ({}) },
  tirando: { type: Number, default: null },
  podeEditar: { type: Boolean, default: true },
  podeEscolherCampos: { type: Boolean, default: false },
  podeConversar: { type: Boolean, default: false },
  podeVerTodas: { type: Boolean, default: false },
  podeAbrirConversas: { type: Boolean, default: false },
  comMidias: { type: Boolean, default: false },
  podeVerTodasAsMidias: { type: Boolean, default: false },
});
const emit = defineEmits([
  'tentar',
  'abrirPessoa',
  'conversar',
  'porPessoa',
  'tirarPessoa',
  'verTodas',
  'abrirConversa',
  'abrirCard',
  'verTodasAsMidias',
  'alterar',
  'escolherCampos',
]);

const podeVer = parte => props.falhas[parte] !== FALHA_DA_PARTE.SEM_ACESSO;
const falhou = parte => props.falhas[parte] === FALHA_DA_PARTE.ERRO;

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-col min-w-0 gap-6 lg:grid lg:grid-cols-3 lg:items-start"
  >
    <div
      data-relacionamentos="coluna-principal"
      class="flex flex-col min-w-0 gap-6 lg:col-span-2"
    >
      <SecaoPessoasDaEmpresa
        v-if="podeVer('pessoas')"
        :pessoas="pessoas"
        :total="totalDePessoas"
        :falhou="falhou('pessoas')"
        :pode-conversar="podeConversar"
        :pode-editar="podeEditar"
        :tirando="tirando"
        @tentar="emit('tentar', 'pessoas')"
        @abrir="pessoaId => emit('abrirPessoa', pessoaId)"
        @conversar="pessoa => emit('conversar', pessoa)"
        @por="emit('porPessoa')"
        @tirar="pessoa => emit('tirarPessoa', pessoa)"
      />
      <slot name="depoisDasPessoas" />
      <SecaoConversas
        v-if="podeVer('conversas')"
        :conversas="conversas"
        :agora="agora"
        :falhou="falhou('conversas')"
        :pode-ver-todas="podeVerTodas"
        :pode-abrir="podeAbrirConversas"
        @tentar="emit('tentar', 'conversas')"
        @ver-todas="emit('verTodas')"
        @abrir="conversaId => emit('abrirConversa', conversaId)"
      />
      <SecaoCards
        v-if="podeVer('cards')"
        :cards="cards"
        :falhou="falhou('cards')"
        @tentar="emit('tentar', 'cards')"
        @abrir="card => emit('abrirCard', card)"
      />
      <SecaoNotas
        v-if="podeVer('notas')"
        :notas="notas"
        :agora="agora"
        :pode-escrever="false"
        :falhou="falhou('notas')"
        :explicacao="t('RELACIONAMENTOS_FICHA.EMPRESA.NOTAS.EXPLICACAO')"
        :vazio="t('RELACIONAMENTOS_FICHA.EMPRESA.NOTAS.VAZIO')"
        @tentar="emit('tentar', 'notas')"
        @abrir-pessoa="pessoaId => emit('abrirPessoa', pessoaId)"
      />
      <SecaoMidias
        v-if="comMidias && podeVer('midias')"
        :midias="midias"
        :agora="agora"
        :falhou="falhou('midias')"
        :pode-ver-todas="podeVerTodasAsMidias"
        @tentar="emit('tentar', 'midias')"
        @ver-todas="emit('verTodasAsMidias')"
      />
    </div>
    <div data-relacionamentos="coluna-lado" class="flex flex-col min-w-0 gap-6">
      <CartaoDeInformacoes
        raiz="RELACIONAMENTOS_FICHA.EMPRESA.INFORMACOES"
        :linhas="linhas"
        :pode-editar="podeEditar"
        :pode-escolher-campos="podeEscolherCampos"
        @alterar="emit('alterar')"
        @escolher-campos="emit('escolherCampos')"
      />
    </div>
  </div>
</template>
