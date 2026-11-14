<script setup>
import { ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import { useErroDoCartao } from '../../../trazer/useErroDoCartao';
import MolduraDoCartao from './MolduraDoCartao.vue';

// #2896, Fatia 2 — o cartão da linha com o telefone errado: o campo de
// telefone, com o número da planilha já escrito nele. O servidor manda o número
// como está na planilha, sem o código do país ("(31) 2345-678"): ele entra no
// campo assim, e o campo o lê como número do Brasil (o país padrão). Só o que
// já vem com "+" traz o país dele.
// A tela só trava o campo vazio e o número em que a pessoa não mexeu. O resto
// vai ao servidor como ela escreveu (o campo manda o número completo, ou o
// código do país e os dígitos enquanto ele não vale), e a recusa diz o motivo.
const props = defineProps({
  problema: { type: Object, required: true },
  frases: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
  recusa: { type: Object, default: null },
});
const emit = defineEmits(['guardar', 'deixarDeFora']);

const { t } = useI18n();

const ERRO_VAZIO = 'RELACIONAMENTOS_TRAZER.PRECISAM.ERRO_PREENCHER';
const ERRO_IGUAL = 'RELACIONAMENTOS_TRAZER.PRECISAM.ERRO_TELEFONE_IGUAL';

const daPlanilha = props.problema.valor || '';
const valor = ref(daPlanilha);
const moldura = ref(null);
const idDoErro = useId();
const { erro, dizer } = useErroDoCartao({
  recusa: () => props.recusa,
  campo: 'telefone',
  raiz: moldura,
  valor,
});

// Salvar fica sempre ligado: o clique diz o que falta e leva o foco ao campo.
const guardar = () => {
  if (props.ocupado) return;
  if (!valor.value) {
    dizer(
      t(ERRO_VAZIO, {
        campo: t('RELACIONAMENTOS_TRAZER.PRECISAM.QUE_FALTA.TELEFONE'),
      })
    );
    return;
  }
  if (valor.value === daPlanilha) {
    dizer(t(ERRO_IGUAL));
    return;
  }
  emit('guardar', props.problema.linha, valor.value);
};
</script>

<template>
  <MolduraDoCartao
    ref="moldura"
    com-salvar
    :linha="problema.linha"
    :frases="frases"
    :erro="erro"
    :id-do-erro="idDoErro"
    :ocupado="ocupado"
    @salvar="guardar"
    @deixar-de-fora="linha => emit('deixarDeFora', linha)"
  >
    <CampoDeTelefone
      v-model="valor"
      alto
      como-escrito
      :erro-descrito-por="erro ? idDoErro : ''"
      :label="t('RELACIONAMENTOS_TRAZER.PRECISAM.CAMPO.TELEFONE')"
      :rotulo-do-pais="t('RELACIONAMENTOS_TRAZER.PRECISAM.CAMPO.PAIS')"
    />
  </MolduraDoCartao>
</template>
