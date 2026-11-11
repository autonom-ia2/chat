<script setup>
import { useI18n } from 'vue-i18n';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import CartaoDaSecao from '../ficha/CartaoDaSecao.vue';
import { ESTADOS_DOS_SEGUROS as ESTADOS } from '../../carteira/useSegurosDe';
import LinhaDoSeguroNaFicha from './LinhaDoSeguroNaFicha.vue';

// #2897 — o bloco Seguros da ficha: o que a pessoa (ou a empresa) tem com a
// corretora. É leitura: não tem botão cheio. Vazio é só uma frase; o erro fica
// dentro do cartão e o resto da ficha continua. Quem usa pode pôr um link
// depois da lista (slot `depois`), que só aparece com os seguros carregados.
defineProps({
  seguros: { type: Array, required: true },
  estado: { type: String, default: ESTADOS.PRONTO },
  daEmpresa: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrir', 'pdf', 'anexar', 'tentar']);

const { t } = useI18n();
const tf = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.FICHA.${chave}`, valores);
</script>

<template>
  <CartaoDaSecao
    :data-carteira="daEmpresa ? 'seguros-da-empresa' : 'seguros'"
    :titulo="
      tf(daEmpresa ? 'TITULO_DA_EMPRESA' : 'TITULO', {
        count: estado === ESTADOS.PRONTO ? seguros.length : 0,
      })
    "
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
        :agora="agora"
        @abrir="emit('abrir', $event)"
        @pdf="emit('pdf', $event)"
        @anexar="emit('anexar', $event)"
      />
    </ul>
    <div
      v-if="estado === ESTADOS.PRONTO && $slots.depois"
      class="flex flex-col items-start gap-2"
    >
      <slot name="depois" />
    </div>
  </CartaoDaSecao>
</template>
