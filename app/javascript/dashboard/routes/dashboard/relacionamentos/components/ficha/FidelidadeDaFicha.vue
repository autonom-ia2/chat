<script setup>
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CartaoDaSecao from './CartaoDaSecao.vue';
import DialogoDarPremio from './DialogoDarPremio.vue';
import FalhaDaParte from './FalhaDaParte.vue';
import SecaoFidelidade from './SecaoFidelidade.vue';
import {
  cupomVencido,
  darPremio,
  fidelidadeDaPessoa,
  movimentosDaPessoa,
  semSaldo,
  usarCodigo,
} from 'dashboard/routes/dashboard/fidelidade/fonte';
import { F } from 'dashboard/routes/dashboard/fidelidade/useTextosDaFidelidade';

// #3100 — o cartão fidelidade dentro da ficha da pessoa: a ficha só põe esta
// peça no lugar (logo depois de Compras); ela mesma lê o servidor. Sem cartão
// na conta, ou sem acesso à leitura, o bloco não aparece. "Ver tudo" traz o
// histórico inteiro, uma página por toque. "Dar o prêmio" é de quem pode mexer
// no contato (`podeEditar`, decisão D1): confirma no DialogoDarPremio e manda
// a chave de idempotência do prêmio. A chave nasce no primeiro toque e é a
// mesma até o servidor responder: se a resposta se perde (rede caiu, demorou
// demais), o toque seguinte repete a mesma chave e o servidor devolve o mesmo
// prêmio, sem tirar a meta duas vezes. Ela só troca depois de uma resposta do
// servidor (o prêmio dado, ou a recusa, que não tirou nada); o 409 quer dizer
// que o primeiro pedido ainda corre, e a chave fica.
// A leitura falhou: o cartão do bloco com "Tentar de novo" (FalhaDaParte), como
// as outras partes da ficha. "Marcar como usado" num cupom da pessoa também é de
// quem pode mexer no contato (D1): a SecaoFidelidade pergunta antes, e o toque
// repetido não gasta de novo (o servidor devolve o código já usado).
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
const chaveDoPremio = ref(null);
const EM_ANDAMENTO = 409;

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

// O servidor respondeu e não está mais com o pedido: o próximo toque é outro.
const servidorRespondeu = falha => {
  const status = falha?.response?.status;
  return Boolean(status) && status !== EM_ANDAMENTO;
};

const confirmarPremio = async () => {
  if (dando.value) return;
  dando.value = true;
  chaveDoPremio.value = chaveDoPremio.value || crypto.randomUUID();
  try {
    const resposta = await darPremio(props.donoId, chaveDoPremio.value);
    chaveDoPremio.value = null;
    dados.value = resposta.fidelidade;
    pagina.value = 0;
    dialogo.value?.close();
    useAlert(t(`${FA}.PREMIO_DADO`, { nome: props.nome }));
  } catch (falha) {
    if (servidorRespondeu(falha)) chaveDoPremio.value = null;
    useAlert(t(`${FA}.${semSaldo(falha) ? 'SEM_SALDO' : 'ERRO_PREMIO'}`));
  } finally {
    dando.value = false;
  }
};

const usando = ref(false);
const usarCupom = async cupom => {
  if (usando.value || !cupom?.id) return;
  usando.value = true;
  try {
    const { codigo } = await usarCodigo(cupom.id);
    const cupons = (dados.value.cupons || []).map(item =>
      item.id === codigo.id ? codigo : item
    );
    dados.value = { ...dados.value, cupons };
    useAlert(t(`${FA}.CUPOM_USADO`, { codigo: codigo.codigo }));
  } catch (falha) {
    useAlert(t(`${FA}.${cupomVencido(falha) ? 'CUPOM_VENCEU' : 'ERRO_CUPOM'}`));
  } finally {
    usando.value = false;
  }
};

watch(
  () => props.donoId,
  () => {
    chaveDoPremio.value = null;
    carregar();
  }
);
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
      :pode-usar-cupom="podeEditar"
      @dar-premio="dialogo?.open()"
      @usar-cupom="usarCupom"
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
