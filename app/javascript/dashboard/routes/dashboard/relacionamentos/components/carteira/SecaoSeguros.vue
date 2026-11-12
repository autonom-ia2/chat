<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import CartaoDaSecao from '../ficha/CartaoDaSecao.vue';
import { ESTADOS_DOS_SEGUROS as ESTADOS } from '../../carteira/useSegurosDe';
import LinhaDoSeguroNaFicha from './LinhaDoSeguroNaFicha.vue';

// #2897 — o bloco Seguros da ficha: o que a pessoa (ou a empresa) tem com a
// corretora, o que pede atenção primeiro. É leitura: não tem botão cheio. Vazio
// é só uma frase; o erro fica dentro do cartão e o resto da ficha continua.
const props = defineProps({
  seguros: { type: Array, required: true },
  estado: { type: String, default: ESTADOS.PRONTO },
  daEmpresa: { type: Boolean, default: false },
  podeGuardar: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrir', 'pdf', 'guardar', 'tentar']);

const { t } = useI18n();
const tf = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.FICHA.${chave}`, valores);

// A contagem só entra no título quando há o que contar.
const titulo = computed(() => {
  const dono = props.daEmpresa ? '_DA_EMPRESA' : '';
  const quantos = props.estado === ESTADOS.PRONTO ? props.seguros.length : 0;
  return quantos
    ? tf(`TITULO_COM_QUANTOS${dono}`, { count: quantos })
    : tf(`TITULO${dono}`);
});
</script>

<template>
  <CartaoDaSecao
    :data-carteira="daEmpresa ? 'seguros-da-empresa' : 'seguros'"
    :titulo="titulo"
  >
    <div v-if="estado === ESTADOS.ERRO" data-carteira="seguros-erro">
      <ErroComTentarDeNovo :mensagem="tf('ERRO')" @tentar="emit('tentar')" />
    </div>
    <EsqueletoDeLista
      v-else-if="estado === ESTADOS.CARREGANDO"
      :linhas="3"
      data-carteira="seguros-carregando"
    />
    <p
      v-else-if="!seguros.length"
      data-carteira="seguros-vazio"
      class="m-0 text-base text-n-slate-11"
    >
      {{ tf('VAZIO') }}
    </p>
    <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
      <LinhaDoSeguroNaFicha
        v-for="seguro in seguros"
        :key="seguro.id"
        :seguro="seguro"
        :pode-guardar="podeGuardar"
        :agora="agora"
        @abrir="emit('abrir', $event)"
        @pdf="emit('pdf', $event)"
        @guardar="emit('guardar', $event)"
      />
    </ul>
  </CartaoDaSecao>
</template>
