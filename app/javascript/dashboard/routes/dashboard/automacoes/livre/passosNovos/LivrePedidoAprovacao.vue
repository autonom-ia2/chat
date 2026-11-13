<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { fraseDoValor } from '../frases';
import { usePodeLerValor } from '../usePodeLerValor';
import { P, PRAZO_PADRAO } from './passosNovos';
import { cardDoPedido, valorDeExemplo } from './adaptadorFalso';
import { duracaoEmFrase, quemEmFrase } from './frasesDosNovos';
import CartaoDoPedido from './CartaoDoPedido.vue';

// #2931 — a prévia do editor: o pedido como quem aprova vai ver, com um card e
// valores de exemplo. A resposta fica só na tela; o pedido de verdade chega na
// tela "Pedidos de aprovação" (AprovacoesPage).
const props = defineProps({
  passo: { type: Object, required: true },
  catalogo: { type: Object, required: true },
});

const { t } = useI18n();
const dialogo = ref(null);
// A peça volta ao começo cada vez que a prévia abre.
const aberturas = ref(0);
const estado = ref(null);
const motivo = ref('');

const VALOR = 'sales_value_view';
const podeLer = usePodeLerValor();
const podeVerValor = computed(() => podeLer.value(VALOR));
const card = computed(() => cardDoPedido(t));

// O dado do texto sai com o valor de exemplo; o valor do card, oculto para
// quem não pode ver valores.
const pergunta = computed(() =>
  (props.passo.pergunta || [])
    .map(parte =>
      typeof parte === 'string'
        ? parte
        : valorDeExemplo(parte.$valor, podeVerValor.value, t) ||
          fraseDoValor(parte.$valor, props.catalogo, t)
    )
    .join('')
    .trim()
);
const linhaDoPrazo = computed(() =>
  t(`${P}.PEDIDO.PRAZO`, {
    prazo: duracaoEmFrase(props.passo.prazo || PRAZO_PADRAO, t),
    quem: quemEmFrase(props.passo.quem, t),
  })
);

const abrir = () => {
  estado.value = null;
  motivo.value = '';
  aberturas.value += 1;
  dialogo.value?.open();
};
const fechar = () => dialogo.value?.close();
const recusar = dito => {
  motivo.value = dito;
  estado.value = 'recusado';
};

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    width="3xl"
    :title="$t(`${P}.PEDIDO.TITULO`)"
    :description="$t(`${P}.PEDIDO.SUBTITULO`)"
    :show-cancel-button="false"
    :show-confirm-button="false"
    overflow-y-auto
  >
    <CartaoDoPedido
      :key="aberturas"
      :pergunta="pergunta"
      :linha-do-prazo="linhaDoPrazo"
      :card="card"
      :com-valor="podeVerValor"
      :estado="estado"
      :motivo-dito="motivo"
      @aprovar="estado = 'aprovado'"
      @recusar="recusar"
    />

    <template #footer>
      <div class="flex justify-end">
        <Button
          data-pedido-fechar
          type="button"
          :label="$t(`${P}.PEDIDO.FECHAR`)"
          slate
          link
          class="min-h-11"
          @click="fechar"
        />
      </div>
    </template>
  </Dialog>
</template>
