<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import { DESTAQUES, cartoesProntos } from '../cartaoPronto';
import { nomeEmUso } from '../nomeDisponivel';
import { useCartao } from './useCartao';
import { useTextos } from './useTextos';
import FuncaoPronta from './FuncaoPronta.vue';
import LinhaRecolhida from './LinhaRecolhida.vue';

// Escolha (#2308, especificação 5.B1): 3 prontas em destaque, "Ver mais" em 2 colunas e "Começar do zero". Uma pronta
// fora do alcance (Financeiro sem ver os custos) sai e deixa só o cadeado.
const emit = defineEmits(['criar', 'zero', 'porPessoa']);

const { giver, canManagePeople, roleLockReason } = usePeopleAccess();
const funcoes = useMapGetter('customRole/getCustomRoles');
const agentes = useMapGetter('agents/getAgents');
const { nome } = useCartao();
const { lista } = useTextos();

const cartoes = computed(() => cartoesProntos(giver.value));
const visiveis = computed(() => cartoes.value.filter(cartao => !cartao.fora));
const destaques = computed(() =>
  visiveis.value.filter(cartao => DESTAQUES.includes(cartao.chave))
);
const mais = computed(() =>
  visiveis.value.filter(cartao => !DESTAQUES.includes(cartao.chave))
);
const fora = computed(() => cartoes.value.filter(cartao => cartao.fora));

const existente = cartao => {
  const funcao = funcoes.value.find(item =>
    nomeEmUso(nome(cartao.chave), [item])
  );
  if (!funcao) return null;
  const pessoas = agentes.value.filter(
    agente => agente.custom_role_id === funcao.id
  ).length;
  return { funcao, pessoas };
};

// "Pôr uma pessoa nela" (especificação 7.8): Pessoas e alcance da função; senão, o motivo (sem Pessoas, nenhum).
const travaDaPessoa = cartao => {
  const achada = existente(cartao);
  if (!achada || !canManagePeople.value) return '';
  return roleLockReason(achada.funcao) || '';
};
const podePorPessoa = cartao =>
  canManagePeople.value && Boolean(existente(cartao)) && !travaDaPessoa(cartao);

const tituloDoMais = computed(() =>
  lista(mais.value.map(cartao => nome(cartao.chave)))
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <header class="flex flex-col gap-2">
      <h1
        class="m-0 text-2xl font-bold tracking-tight sm:text-3xl text-n-slate-12"
      >
        {{ $t('FUNCOES_EQUIPE.ESCOLHA.TITULO') }}
      </h1>
      <p class="m-0 text-base text-n-slate-11">
        {{ $t('FUNCOES_EQUIPE.ESCOLHA.DICA') }}
      </p>
    </header>

    <ul class="grid gap-4 p-0 m-0 list-none md:grid-cols-3">
      <FuncaoPronta
        v-for="cartao in destaques"
        :key="cartao.chave"
        :cartao="cartao"
        :existente="existente(cartao)"
        :pode-por-pessoa="podePorPessoa(cartao)"
        :trava-da-pessoa="travaDaPessoa(cartao)"
        @criar="emit('criar', cartao.chave)"
        @por-pessoa="emit('porPessoa', existente(cartao).funcao)"
      />
    </ul>

    <LinhaRecolhida
      v-if="mais.length"
      icone="i-lucide-layout-grid"
      :titulo="$t('FUNCOES_EQUIPE.ESCOLHA.VER_MAIS', { n: mais.length })"
      :estado="tituloDoMais"
    >
      <ul class="grid gap-4 p-4 m-0 list-none md:grid-cols-2">
        <FuncaoPronta
          v-for="cartao in mais"
          :key="cartao.chave"
          :cartao="cartao"
          :existente="existente(cartao)"
          :pode-por-pessoa="podePorPessoa(cartao)"
          :trava-da-pessoa="travaDaPessoa(cartao)"
          @criar="emit('criar', cartao.chave)"
          @por-pessoa="emit('porPessoa', existente(cartao).funcao)"
        />
      </ul>
    </LinhaRecolhida>

    <div class="flex flex-wrap items-center justify-between gap-3">
      <button
        type="button"
        data-zero
        class="inline-flex items-center gap-2 px-4 text-sm font-medium rounded-xl min-h-11 bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="emit('zero')"
      >
        <span class="i-lucide-plus size-4" aria-hidden="true" />
        {{ $t('FUNCOES_EQUIPE.ESCOLHA.ZERO') }}
      </button>
      <p
        v-for="cartao in fora"
        :key="cartao.chave"
        data-fora
        class="flex items-center gap-1.5 m-0 text-sm text-n-slate-11"
      >
        <span class="i-lucide-lock size-4 shrink-0" aria-hidden="true" />
        {{ $t('FUNCOES_EQUIPE.ESCOLHA.FORA', { nome: nome(cartao.chave) }) }}
      </p>
    </div>
  </div>
</template>
