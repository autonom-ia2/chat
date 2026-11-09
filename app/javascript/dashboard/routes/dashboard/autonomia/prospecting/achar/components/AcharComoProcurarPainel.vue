<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AcharPainel from './AcharPainel.vue';
import AcharEscolhaCartao from './AcharEscolhaCartao.vue';

// #2692 — painel "Como procurar" (v4, T0p): distância, quais e quantas, cada
// um em cartões de um toque. Nada muda até "Salvar" (molde LivreAlterar.vue).
// Rodada 2: "Seus modelos" (os modelos salvos da conta viram cartões) e o link
// "Mais ajustes", que abre o painel de ajustes finos por cima.
// Rodada 5: os modelos da conta ficam no bloco próprio "Quais empresas" (só
// aparece quando há modelo). "Quem vem primeiro" voltou para "Mais ajustes",
// como o Rodrigo decidiu; o padrão segue "as melhores". Painel de primeiro
// nível: sai pelo "Fechar" do topo, sem "Cancelar" no rodapé.
const props = defineProps({
  como: { type: Object, required: true },
  modelos: { type: Array, default: () => [] },
});
const emit = defineEmits(['salvar', 'maisAjustes', 'close']);

const NS = 'PROSPECTING_ACHAR.COMO_PROCURAR';
const DISTANCIAS = [1, 3, 5, 10];
const QUANTAS = [20, 40, 60];

const rascunho = ref({ ...props.como });
const mudar = (campo, valor) => {
  rascunho.value = { ...rascunho.value, [campo]: valor };
};
</script>

<template>
  <AcharPainel :titulo="$t(`${NS}.TITULO`)" @close="emit('close')">
    <section class="flex flex-col gap-3">
      <h3 class="m-0 text-lg font-semibold text-n-slate-12">
        {{ $t(`${NS}.ATE_ONDE.TITULO`) }}
      </h3>
      <div role="radiogroup" class="grid gap-3 sm:grid-cols-2">
        <AcharEscolhaCartao
          v-for="km in DISTANCIAS"
          :key="km"
          :titulo="$t(`${NS}.ATE_ONDE.KM_${km}`)"
          :escolhido="rascunho.km === km"
          @escolher="mudar('km', km)"
        />
      </div>
    </section>
    <section v-if="modelos.length" class="flex flex-col gap-3">
      <h3 class="m-0 text-lg font-semibold text-n-slate-12">
        {{ $t(`${NS}.QUAIS.TITULO`) }}
      </h3>
      <div role="radiogroup" class="grid gap-3" data-modelos>
        <AcharEscolhaCartao
          :titulo="$t(`${NS}.QUAIS.TODAS`)"
          :escolhido="rascunho.quais === 'todas'"
          @escolher="mudar('quais', 'todas')"
        />
        <AcharEscolhaCartao
          v-for="modelo in modelos"
          :key="modelo.id"
          :titulo="modelo.nome"
          :selo="$t(`${NS}.SEU`)"
          :escolhido="rascunho.quais === modelo.id"
          data-modelo
          @escolher="mudar('quais', modelo.id)"
        />
      </div>
    </section>
    <section class="flex flex-col gap-3">
      <h3 class="m-0 text-lg font-semibold text-n-slate-12">
        {{ $t(`${NS}.QUANTAS.TITULO`) }}
      </h3>
      <div role="radiogroup" class="grid gap-3">
        <AcharEscolhaCartao
          v-for="n in QUANTAS"
          :key="n"
          :titulo="$t(`${NS}.QUANTAS.N_${n}`)"
          :escolhido="rascunho.n === n"
          @escolher="mudar('n', n)"
        />
      </div>
    </section>
    <button
      type="button"
      class="flex items-center self-start gap-1.5 px-1 text-sm font-medium min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      data-mais-ajustes
      @click="emit('maisAjustes', rascunho)"
    >
      <span class="i-lucide-sliders-horizontal size-4" aria-hidden="true" />
      {{ $t(`${NS}.MAIS_AJUSTES`) }}
    </button>
    <template #rodape>
      <Button
        :label="$t('PROSPECTING_ACHAR.COMUM.USAR_ESCOLHA')"
        class="!min-h-12 !rounded-xl !text-base"
        data-salvar
        @click="emit('salvar', rascunho)"
      />
    </template>
  </AcharPainel>
</template>
