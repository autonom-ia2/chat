<script setup>
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../AgenteBotao.vue';
import CartaoInformacao from './CartaoInformacao.vue';
import { novaInformacao } from '../../../utils/ferramentas';

// #1301 (protótipo F05) — as informações que o agente tira da conversa. #1430: é o passo 2, antes do
// link, para o passo 3 oferecer cada uma pelo nome de gente ("CEP") na hora de montar o link. O que
// vai junto e o recorte da resposta foram para Avançado, no passo 3.
const props = defineProps({
  rascunho: { type: Object, required: true },
  base: { type: String, required: true },
  erros: { type: Object, required: true },
});

const emit = defineEmits(['update:rascunho', 'anunciar']);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS.PASSOS.TRES';
const { t } = useI18n();

const mudarInformacoes = informacoes =>
  emit('update:rascunho', { ...props.rascunho, informacoes });

const mudarInformacao = (indice, informacao) =>
  mudarInformacoes(
    props.rascunho.informacoes.map((item, i) =>
      i === indice ? informacao : item
    )
  );

const adicionar = () =>
  mudarInformacoes([...props.rascunho.informacoes, novaInformacao()]);

const remover = indice => {
  mudarInformacoes(props.rascunho.informacoes.filter((_, i) => i !== indice));
  emit('anunciar', t(`${NS}.REMOVIDA`));
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <p class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.INTRO`) }}
    </p>
    <div class="flex flex-col gap-3">
      <CartaoInformacao
        v-for="(informacao, indice) in rascunho.informacoes"
        :key="informacao.id"
        :informacao="informacao"
        :indice="indice"
        :base="base"
        :erro="
          erros[`i${indice}`] ? t(`${NS}.ERRO.${erros[`i${indice}`]}`) : ''
        "
        @update:informacao="mudarInformacao(indice, $event)"
        @remover="remover(indice)"
      />
      <p
        v-if="!rascunho.informacoes.length"
        data-sem-informacao
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t(`${NS}.NENHUMA`) }}
      </p>
    </div>
    <AgenteBotao
      :id="`${base}-adicionar-informacao`"
      data-adicionar-informacao
      variante="contorno"
      icone="i-lucide-plus"
      class="self-start"
      @click="adicionar"
    >
      {{ t(`${NS}.ADICIONAR`) }}
    </AgenteBotao>
  </div>
</template>
