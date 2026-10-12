<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../AgenteBotao.vue';
import AgenteConfirmacao from '../../AgenteConfirmacao.vue';
import CartaoCabecalho from './CartaoCabecalho.vue';
import FerramentaFaixa from './FerramentaFaixa.vue';
import { novoCabecalho } from '../../../utils/ferramentas';

// #1301 (protótipos F06 e F10) — passo 4: chaves de acesso e cabeçalhos. Content-Type e Accept não
// aparecem porque o sistema já os põe. Tirar um segredo guardado pede confirmação (a chave é apagada
// ao salvar). Na criação, a faixa avisa que a ferramenta é salva desligada.
const props = defineProps({
  rascunho: { type: Object, required: true },
  base: { type: String, required: true },
  erros: { type: Object, required: true },
  novo: { type: Boolean, default: false },
});

const emit = defineEmits(['update:rascunho', 'anunciar']);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS.PASSOS.QUATRO';
const { t } = useI18n();
const VARIAVEL = '{{nome}}';

const confirmacao = ref(null);
const aRemover = ref(null);

const mudarCabecalhos = cabecalhos =>
  emit('update:rascunho', { ...props.rascunho, cabecalhos });

const mudarCabecalho = (indice, cabecalho) =>
  mudarCabecalhos(
    props.rascunho.cabecalhos.map((item, i) =>
      i === indice ? cabecalho : item
    )
  );

const adicionar = () =>
  mudarCabecalhos([...props.rascunho.cabecalhos, novoCabecalho()]);

const removerAgora = indice => {
  mudarCabecalhos(props.rascunho.cabecalhos.filter((_, i) => i !== indice));
  emit('anunciar', t(`${NS}.REMOVIDO`));
  document.getElementById(`${props.base}-adicionar-cabecalho`)?.focus();
};

const pedirRemover = indice => {
  const cabecalho = props.rascunho.cabecalhos[indice];
  if (!(cabecalho.segredo && cabecalho.guardado)) {
    removerAgora(indice);
    return;
  }
  aRemover.value = indice;
  confirmacao.value?.abrir();
};

const confirmarRemover = () => {
  const indice = aRemover.value;
  confirmacao.value?.fechar();
  if (indice !== null) removerAgora(indice);
};

// O erro CHAVE é do nome do cabeçalho; os outros, do valor.
const erroDo = (indice, campo) => {
  const erro = props.erros[`c${indice}`];
  if (!erro || (erro === 'CHAVE') !== (campo === 'chave')) return '';
  return t(`${NS}.ERRO.${erro}`);
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.INTRO`) }}</p>
    <div class="flex flex-col gap-3">
      <CartaoCabecalho
        v-for="(cabecalho, indice) in rascunho.cabecalhos"
        :key="cabecalho.id"
        :cabecalho="cabecalho"
        :indice="indice"
        :base="base"
        :erro="erroDo(indice, 'valor')"
        :erro-chave="erroDo(indice, 'chave')"
        @update:cabecalho="mudarCabecalho(indice, $event)"
        @remover="pedirRemover(indice)"
      />
      <p
        v-if="!rascunho.cabecalhos.length"
        data-sem-cabecalho
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t(`${NS}.NENHUM`) }}
      </p>
    </div>
    <AgenteBotao
      :id="`${base}-adicionar-cabecalho`"
      data-adicionar-cabecalho
      variante="contorno"
      icone="i-lucide-plus"
      class="self-start"
      @click="adicionar"
    >
      {{ t(`${NS}.ADICIONAR`) }}
    </AgenteBotao>
    <p class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.NOTA`, { variavel: VARIAVEL }) }}
    </p>
    <FerramentaFaixa
      v-if="novo"
      data-salva-desligada
      tom="azul"
      icone="i-lucide-power"
    >
      <p class="m-0">{{ t(`${NS}.SALVA_DESLIGADA`) }}</p>
    </FerramentaFaixa>
    <AgenteConfirmacao
      ref="confirmacao"
      :titulo="t(`${NS}.REMOVER_TITULO`)"
      :texto="t(`${NS}.REMOVER_TEXTO`)"
      :confirmar="t('AGENTS.JORNADA.PAGINA.FERRAMENTAS.REMOVER')"
      @confirmar="confirmarRemover"
      @fechada="aRemover = null"
    />
  </div>
</template>
