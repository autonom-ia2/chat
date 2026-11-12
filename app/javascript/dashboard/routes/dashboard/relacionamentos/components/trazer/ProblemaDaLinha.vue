<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  CARTOES,
  campoDoProblema,
  cartaoDoProblema,
  ehRepetida,
  temAsDuasLinhas,
} from '../../trazer/cartaoDoProblema';
import { SITUACAO_DO_PROBLEMA } from '../../trazer/contagem';
import {
  chaveDoCampoComFormula,
  chaveDoTexto,
} from '../../trazer/textoDoProblema';
import CartaoDaRepetida from './problema/CartaoDaRepetida.vue';
import CartaoDoTelefone from './problema/CartaoDoTelefone.vue';
import CartaoDoTexto from './problema/CartaoDoTexto.vue';
import CartaoSemConserto from './problema/CartaoSemConserto.vue';
import LinhaRecolhida from './problema/LinhaRecolhida.vue';

// #2894 — uma linha da planilha que precisa da pessoa: o problema em palavras
// simples e o conserto ali mesmo (telefone, e-mail, nome, qual duplicada fica).
// Consertou: vira "Pronto ✓". Guardar e Deixar de fora saem como evento.
// #2896 — `semConserto` (a planilha já foi apagada do servidor): a linha diz o
// problema e só oferece "Deixar de fora"; o conserto não existe ali. E a linha
// repetida pode vir sem a outra linha (`outraLinha` vazio): aí não há o que
// comparar nem escolher.
// Fatia 2 — `recusa` (`{ linha, motivo }`): o servidor não aceitou o valor que a
// pessoa escreveu. A linha diz a frase do motivo ali mesmo, como alerta, e leva
// o foco ao campo. A frase do problema é a do motivo, quando o servidor o diz
// (trazer/textoDoProblema.js); a linha guardada mostra o valor que ficou salvo.
// A linha já recolhida também recebe a recusa: é o "Voltar atrás" que falhou.
// Esta é a casca: decide as frases da linha e escolhe o cartão dela, um
// componente por tipo (components/trazer/problema/ e trazer/cartaoDoProblema.js).
const props = defineProps({
  problema: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
  semConserto: { type: Boolean, default: false },
  recusa: { type: Object, default: null },
});
const emit = defineEmits(['guardar', 'deixarDeFora', 'reabrir']);

const { t } = useI18n();

const aberto = computed(
  () => props.problema.estado === SITUACAO_DO_PROBLEMA.ABERTO
);
const guardado = computed(
  () => props.problema.estado === SITUACAO_DO_PROBLEMA.GUARDADO
);
const campo = computed(() => campoDoProblema(props.problema));
const cartao = computed(() =>
  cartaoDoProblema(props.problema, props.semConserto)
);
const temAsDuas = computed(() => temAsDuasLinhas(props.problema));

// Quem é, em palavras da pessoa: o nome; sem nome, o telefone ou e-mail que
// houver; sem nada, a linha. A linha da planilha vai como apoio, em cinza.
const quem = computed(
  () =>
    props.problema.nome ||
    props.problema.contato ||
    t('RELACIONAMENTOS_TRAZER.PRECISAM.QUEM_SEM_NOME', {
      linha: props.problema.linha,
    })
);
// Na linha com fórmula, o campo em que ela está, no nome que a tela dá a ele.
const campoComFormula = computed(() => {
  const chave = chaveDoCampoComFormula(props.problema);
  return chave ? t(chave) : '';
});
const texto = computed(() =>
  ehRepetida(props.problema) && (props.semConserto || !temAsDuas.value)
    ? t('RELACIONAMENTOS_TRAZER.PRECISAM.PROBLEMA.DUPLICADA_SEM_ESCOLHA', {
        quem: quem.value,
      })
    : t(chaveDoTexto(props.problema), {
        quem: quem.value,
        campo: campoComFormula.value,
        valor: props.problema.corrigido,
      })
);
const apoio = computed(() =>
  temAsDuas.value
    ? t('RELACIONAMENTOS_TRAZER.PRECISAM.LINHAS_DA_PLANILHA', {
        linha: props.problema.linha,
        outraLinha: props.problema.outraLinha,
      })
    : t('RELACIONAMENTOS_TRAZER.PRECISAM.LINHA_DA_PLANILHA', {
        linha: props.problema.linha,
      })
);
// O valor como está na planilha. No telefone ele já está no campo; na repetida,
// nos cartões das duas linhas.
const naPlanilha = computed(() =>
  props.problema.valor &&
  campo.value !== 'telefone' &&
  !ehRepetida(props.problema)
    ? t('RELACIONAMENTOS_TRAZER.PRECISAM.NA_PLANILHA', {
        valor: props.problema.valor,
      })
    : ''
);

// O que todo cartão aberto recebe.
const doCartao = computed(() => ({
  problema: props.problema,
  frases: {
    texto: texto.value,
    apoio: apoio.value,
    naPlanilha: naPlanilha.value,
  },
  ocupado: props.ocupado,
  recusa: props.recusa,
}));

const guardar = (linha, valor) => emit('guardar', linha, valor);
const deixarDeFora = linha => emit('deixarDeFora', linha);
</script>

<template>
  <li
    :data-linha="problema.linha"
    class="flex flex-col gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <LinhaRecolhida
      v-if="!aberto"
      :linha="problema.linha"
      :texto="texto"
      :guardada="guardado"
      :ocupado="ocupado"
      :recusa="recusa"
      @reabrir="linha => emit('reabrir', linha)"
    />
    <CartaoSemConserto
      v-else-if="cartao === CARTOES.SEM_CONSERTO"
      v-bind="doCartao"
      :campo="campo"
      @deixar-de-fora="deixarDeFora"
    />
    <CartaoDoTelefone
      v-else-if="cartao === CARTOES.TELEFONE"
      v-bind="doCartao"
      @guardar="guardar"
      @deixar-de-fora="deixarDeFora"
    />
    <CartaoDaRepetida
      v-else-if="cartao === CARTOES.REPETIDA"
      v-bind="doCartao"
      @guardar="guardar"
      @deixar-de-fora="deixarDeFora"
    />
    <CartaoDoTexto
      v-else
      v-bind="doCartao"
      :campo="campo"
      @guardar="guardar"
      @deixar-de-fora="deixarDeFora"
    />
  </li>
</template>
