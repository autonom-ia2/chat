<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import HeroiEscuro from 'dashboard/routes/dashboard/relacionamentos/components/comum/HeroiEscuro.vue';
import AbasDaFidelidade from './AbasDaFidelidade.vue';
import PainelDoCartao from './PainelDoCartao.vue';
import ConferirCupom from './cupons/ConferirCupom.vue';
import ListaDeCupons from './cupons/ListaDeCupons.vue';
import { F, useTextosDaFidelidade } from '../useTextosDaFidelidade';
import { PAINEL_DA_FIDELIDADE, idDaAbaDaFidelidade } from '../abas';

// #3100 — a tela Fidelidade (menu Crescer), sem buscar nada: quem usa (a
// página, com a fonte do servidor) entrega o programa, o resumo e os cupons.
// Aba "Cartão fidelidade": sem programa, o herói com "Criar meu cartão
// fidelidade" (só para quem pode; quem só vê lê que ainda não há cartão); com
// programa, o painel. Aba "Cupons": o conferir no topo (o cliente mostrou um
// código) e o relatório, onde cada cupom pausa, liga de novo e, ainda não
// mandado, abre a automação pronta (`mandarCupom`). `programa` nulo é "a conta
// ainda não criou"; `carregando` é antes da primeira resposta. `comCupons`
// falso esconde as abas e mostra só o cartão (o cupom chega na etapa dele).
// `podeUsarCupom`: quem pode mexer no contato vê "Marcar como usado" no conferir.
defineProps({
  aba: { type: String, required: true },
  programa: { type: Object, default: null },
  resumo: { type: Object, default: null },
  cupons: { type: Array, default: null },
  carregando: { type: Boolean, default: false },
  podeMudar: { type: Boolean, default: false },
  agora: { type: Number, required: true },
  conferencia: { type: Object, default: () => ({}) },
  comCupons: { type: Boolean, default: true },
  podeUsarCupom: { type: Boolean, default: false },
});
const emit = defineEmits([
  'update:aba',
  'criar',
  'mudar',
  'verPerto',
  'pausar',
  'ligar',
  'criarCupom',
  'conferir',
  'usarCupom',
  'mandarCupom',
  'pausarCupom',
  'ligarCupom',
]);

const { t } = useTextosDaFidelidade();
</script>

<template>
  <div data-fidelidade="tela" class="flex flex-col gap-6">
    <header class="flex flex-col gap-1">
      <h1
        data-titulo-da-tela
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight outline-none text-n-slate-12 md:text-3xl"
      >
        {{ t(`${F}.TITULO`) }}
      </h1>
      <p class="m-0 text-base text-n-slate-11">{{ t(`${F}.APOIO`) }}</p>
    </header>

    <AbasDaFidelidade
      v-if="comCupons"
      :model-value="aba"
      @update:model-value="nova => emit('update:aba', nova)"
    />

    <div
      :id="PAINEL_DA_FIDELIDADE"
      :role="comCupons ? 'tabpanel' : undefined"
      :aria-labelledby="comCupons ? idDaAbaDaFidelidade(aba) : undefined"
      class="flex flex-col gap-6"
    >
      <template v-if="aba === 'cartao' || !comCupons">
        <div
          v-if="carregando"
          data-fidelidade="carregando"
          aria-busy="true"
          class="h-72 rounded-3xl bg-n-alpha-2 animate-pulse"
        />
        <HeroiEscuro v-else-if="!programa" data-fidelidade="vazio">
          <template #frase>{{ t(`${F}.VAZIO.FRASE`) }}</template>
          <template #apoio>
            {{ podeMudar ? t(`${F}.VAZIO.APOIO`) : t(`${F}.VAZIO.SEM_PODER`) }}
          </template>
          <template v-if="podeMudar" #acao>
            <Button
              data-fidelidade="criar"
              size="lg"
              icon="i-lucide-gift"
              class="min-h-11"
              :label="t(`${F}.VAZIO.BOTAO`)"
              @click="emit('criar')"
            />
          </template>
        </HeroiEscuro>
        <PainelDoCartao
          v-else
          :programa="programa"
          :resumo="resumo"
          :pode-mudar="podeMudar"
          @mudar="emit('mudar')"
          @ver-perto="emit('verPerto')"
          @pausar="emit('pausar')"
          @ligar="emit('ligar')"
        />
      </template>

      <template v-else>
        <ConferirCupom
          v-if="cupons && cupons.length"
          :agora="agora"
          :resultado="conferencia.resultado || null"
          :conferindo="Boolean(conferencia.conferindo)"
          :usando="Boolean(conferencia.usando)"
          :usado="Boolean(conferencia.usado)"
          :codigo-inicial="conferencia.codigo || ''"
          :pode-usar="podeUsarCupom"
          @conferir="codigo => emit('conferir', codigo)"
          @usar="emit('usarCupom')"
        />
        <ListaDeCupons
          :cupons="cupons"
          :pode-mudar="podeMudar"
          @criar="emit('criarCupom')"
          @mandar="cupom => emit('mandarCupom', cupom)"
          @pausar="cupom => emit('pausarCupom', cupom)"
          @ligar="cupom => emit('ligarCupom', cupom)"
        />
      </template>
    </div>
  </div>
</template>
