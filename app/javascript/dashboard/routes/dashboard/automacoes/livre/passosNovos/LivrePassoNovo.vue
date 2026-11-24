<script setup>
import { onMounted, ref } from 'vue';
import { useEventListener } from '@vueuse/core';
import { useRouter } from 'vue-router';
import LivreAprovacao from './LivreAprovacao.vue';
import LivreRepetir from './LivreRepetir.vue';
import LivreBloco from './LivreBloco.vue';
import LivreConsulta from './LivreConsulta.vue';
import LivreReuniao from './LivreReuniao.vue';
import LivrePesquisa from './LivrePesquisa.vue';
import LivreDarCarimbos from './LivreDarCarimbos.vue';
import LivreMandarCupom from './LivreMandarCupom.vue';
import {
  carregarProgramaDaConta,
  esquecerProgramaDaConta,
  programaDaConta,
  relerProgramaDaConta,
} from 'dashboard/routes/dashboard/fidelidade/programaDaConta';
import {
  carregarCuponsDaConta,
  cuponsDaConta,
  esquecerCuponsDaConta,
  relerCuponsDaConta,
} from 'dashboard/routes/dashboard/fidelidade/cuponsDaConta';
import LivrePassoNovoPrevia from './LivrePassoNovoPrevia.vue';
import { P, emTeste } from './passosNovos';

// #2931–#2936 — a peça do "Alterar" para os passos novos: o formulário de cada
// um, já pronto, e a prévia do ensaio e do histórico. O passo inteiro entra e
// sai por `modelValue`, como no "para cada item" (G24). O aviso "em teste" só
// num passo novo que o servidor ainda não conheça (emTeste; hoje, nenhum).
// #3100 — "Dar carimbos ou pontos" lê o cartão fidelidade da conta; sem ele,
// "Criar cartão fidelidade" abre a tela de montar em outra aba, para a
// automação em montagem não se perder. "Mandar cupom" lê os cupons da conta do
// mesmo jeito; sem nenhum, "Criar cupom" abre a tela de criar em outra aba.
// Quando a pessoa volta para esta aba (visibilitychange/focus), o passo relê o
// cartão ou os cupons: quem acabou de criar já vê o que criou. Os ouvintes
// saem junto com o passo (useEventListener).
const props = defineProps({
  modelValue: { type: Object, required: true },
  catalogo: { type: Object, required: true },
  opcoes: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
  etapas: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);
const mudar = novo => emit('update:modelValue', novo);

const router = useRouter();
const criarPrograma = () => {
  esquecerProgramaDaConta();
  window.open(router.resolve({ name: 'fidelidade_montar' }).href, '_blank');
};
const criarCupom = () => {
  esquecerCuponsDaConta();
  window.open(router.resolve({ name: 'fidelidade_cupom_novo' }).href, '_blank');
};
const LEITURAS = {
  dar_carimbos: carregarProgramaDaConta,
  mandar_cupom: carregarCuponsDaConta,
};
const RELEITURAS = {
  dar_carimbos: relerProgramaDaConta,
  mandar_cupom: relerCuponsDaConta,
};
const lendo = ref(Boolean(LEITURAS[props.modelValue.tipo]));
const agora = Date.now();
onMounted(async () => {
  if (!lendo.value) return;
  await LEITURAS[props.modelValue.tipo]();
  lendo.value = false;
});

// Voltar à aba dispara os dois eventos juntos: uma leitura por vez basta.
let relendo = false;
const reler = async () => {
  const releitura = RELEITURAS[props.modelValue.tipo];
  if (!releitura || relendo || document.visibilityState !== 'visible') return;
  relendo = true;
  try {
    await releitura();
  } finally {
    relendo = false;
  }
};
if (RELEITURAS[props.modelValue.tipo]) {
  useEventListener(document, 'visibilitychange', reler);
  useEventListener(window, 'focus', reler);
}
</script>

<template>
  <div class="flex flex-col gap-6" data-peca="passo_novo">
    <p
      v-if="emTeste(modelValue)"
      data-em-teste
      role="note"
      class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-blue-2 text-n-blue-12"
    >
      {{ $t(`${P}.EM_TESTE`) }}
    </p>

    <LivreAprovacao
      v-if="modelValue.tipo === 'pedir_aprovacao'"
      :model-value="modelValue"
      :catalogo="catalogo"
      :opcoes="opcoes"
      :atributos-do="atributosDo"
      @update:model-value="mudar"
    />
    <LivreRepetir
      v-else-if="modelValue.tipo === 'repetir_lista'"
      :model-value="modelValue"
      :opcoes="opcoes"
      :etapas="etapas"
      @update:model-value="mudar"
    />
    <LivreBloco
      v-else-if="modelValue.tipo === 'usar_bloco'"
      :model-value="modelValue"
      :catalogo="catalogo"
      @update:model-value="mudar"
    />
    <LivreConsulta
      v-else-if="modelValue.tipo === 'consultar'"
      :model-value="modelValue"
      :catalogo="catalogo"
      :atributos-do="atributosDo"
      @update:model-value="mudar"
    />
    <LivreReuniao
      v-else-if="modelValue.tipo === 'marcar_reuniao'"
      :model-value="modelValue"
      :catalogo="catalogo"
      :opcoes="opcoes"
      :atributos-do="atributosDo"
      @update:model-value="mudar"
    />
    <LivrePesquisa
      v-else-if="modelValue.tipo === 'pesquisa_nota'"
      :model-value="modelValue"
      :catalogo="catalogo"
      :atributos-do="atributosDo"
      @update:model-value="mudar"
    />
    <div
      v-else-if="lendo"
      aria-busy="true"
      class="h-40 rounded-2xl bg-n-alpha-2 animate-pulse"
    />
    <LivreDarCarimbos
      v-else-if="modelValue.tipo === 'dar_carimbos'"
      :model-value="modelValue"
      :programa="programaDaConta()"
      @update:model-value="mudar"
      @criar-programa="criarPrograma"
    />
    <LivreMandarCupom
      v-else-if="modelValue.tipo === 'mandar_cupom'"
      :model-value="modelValue"
      :cupons="cuponsDaConta()"
      :catalogo="catalogo"
      :atributos-do="atributosDo"
      :agora="agora"
      @update:model-value="mudar"
      @criar-cupom="criarCupom"
    />

    <LivrePassoNovoPrevia :passo="modelValue" />
  </div>
</template>
