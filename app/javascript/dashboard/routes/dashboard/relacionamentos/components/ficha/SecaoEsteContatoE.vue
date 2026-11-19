<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import EscolhaDaRelacao from 'dashboard/components-next/contato-relacao/EscolhaDaRelacao.vue';
import { ESTADO } from 'dashboard/components-next/painel-do-contato/useParteDoPainel';
import CartaoDaSecao from './CartaoDaSecao.vue';

// #3075 — "Este contato é" (interessado, parceiro do mercado, não é negócio)
// na ficha nova, atrás da chave `contato_relacao`: a mesma escolha da ficha
// antiga e do painel da conversa (contato-relacao/EscolhaDaRelacao.vue), com a
// pergunta de arquivar o card aberto, no cartão da ficha nova. Como na antiga
// (SecaoDaRelacao), sem acesso ou com a chave desligada no servidor o cartão
// inteiro some. Quem só pode ver (`podeEditar` falso) lê a escolha sem mudar.
defineProps({
  pessoaId: { type: Number, required: true },
  podeEditar: { type: Boolean, default: false },
});

const { t } = useI18n();
const estado = ref(ESTADO.CARREGANDO);
const visivel = computed(
  () => ![ESTADO.ESCONDIDO, ESTADO.VAZIO].includes(estado.value)
);
</script>

<template>
  <CartaoDaSecao
    v-show="visivel"
    :titulo="t('PAINEL_DO_CONTATO.RELACAO.TITULO')"
    data-relacionamentos="este-contato-e"
  >
    <EscolhaDaRelacao
      :contact-id="pessoaId"
      :pode-editar="podeEditar"
      @estado="estado = $event"
    />
  </CartaoDaSecao>
</template>
