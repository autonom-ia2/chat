<script setup>
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CartaoDaSecao from './CartaoDaSecao.vue';
import DialogoDarPremio from './DialogoDarPremio.vue';
import FalhaDaParte from './FalhaDaParte.vue';
import SecaoFidelidade from './SecaoFidelidade.vue';
import {
  darPremio,
  fidelidadeDaPessoa,
  movimentosDaPessoa,
  semSaldo,
} from 'dashboard/routes/dashboard/fidelidade/fonte';
import { F } from 'dashboard/routes/dashboard/fidelidade/useTextosDaFidelidade';

// #3100 — o cartão fidelidade dentro da ficha da pessoa: a ficha só põe esta
// peça no lugar (logo depois de Compras); ela mesma lê o servidor. Sem cartão
// na conta, ou sem acesso à leitura, o bloco não aparece. "Ver tudo" traz o
// histórico inteiro, uma página por toque. "Dar o prêmio" é de quem pode mexer
// no contato (`podeEditar`, decisão D1): confirma no DialogoDarPremio e manda
// uma chave por toque, para um clique repetido não tirar a meta duas vezes.
// A leitura falhou: o cartão do bloco com "Tentar de novo" (FalhaDaParte), como
// as outras partes da ficha. Marcar cupom como usado chega com a etapa dos cupons.
const props = defineProps({
  donoId: { type: Number, required: true },
  nome: { type: String, default: '' },
  agora: { type: Number, required: true },
  podeEditar: { type: Boolean, default: false },
});

const { t } = useI18n();
const FA = `${F}.FICHA_ACOES`;
const SEM_ACESSO = [401, 403];

const dados = ref(null);
const falhou = ref(false);
const pagina = ref(0);
const dando = ref(false);
const dialogo = ref(null);

const carregar = async () => {
  falhou.value = false;
  pagina.value = 0;
  try {
    dados.value = (await fidelidadeDaPessoa(props.donoId)) || null;
  } catch (falha) {
    dados.value = null;
    falhou.value = !SEM_ACESSO.includes(falha?.response?.status);
  }
};

// A primeira página já traz os 5 da ficha; as seguintes se juntam embaixo.
const verTudo = async () => {
  try {
    const proxima = pagina.value + 1;
    const { itens } = await movimentosDaPessoa(props.donoId, proxima);
    const antes = proxima === 1 ? [] : dados.value.historico;
    dados.value = { ...dados.value, historico: [...antes, ...itens] };
    pagina.value = proxima;
  } catch {
    useAlert(t(`${FA}.ERRO_HISTORICO`));
  }
};

const confirmarPremio = async () => {
  if (dando.value) return;
  dando.value = true;
  try {
    const resposta = await darPremio(props.donoId, crypto.randomUUID());
    dados.value = resposta.fidelidade;
    pagina.value = 0;
    dialogo.value?.close();
    useAlert(t(`${FA}.PREMIO_DADO`, { nome: props.nome }));
  } catch (falha) {
    useAlert(t(`${FA}.${semSaldo(falha) ? 'SEM_SALDO' : 'ERRO_PREMIO'}`));
  } finally {
    dando.value = false;
  }
};

watch(() => props.donoId, carregar);
onMounted(carregar);
</script>

<template>
  <div v-if="dados?.programa || falhou" data-fidelidade="da-ficha">
    <SecaoFidelidade
      v-if="dados?.programa"
      :programa="dados.programa"
      :saldo="dados"
      :agora="agora"
      :pode-dar-premio="podeEditar"
      @dar-premio="dialogo?.open()"
      @ver-tudo="verTudo"
      @tentar="carregar"
    />
    <CartaoDaSecao v-else :titulo="t(`${F}.FICHA.TITULO`)">
      <FalhaDaParte @tentar="carregar" />
    </CartaoDaSecao>
    <DialogoDarPremio
      v-if="dados?.programa"
      ref="dialogo"
      :programa="dados.programa"
      :tem="dados.tem"
      :nome="nome"
      :carregando="dando"
      @confirmar="confirmarPremio"
    />
  </div>
</template>
