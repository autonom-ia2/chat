<script setup>
import { ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import { CAMPO_CONTATO } from '../../../trazer/cartaoDoProblema';
import { LIMITES } from '../../../trazer/limites';
import { useErroDoCartao } from '../../../trazer/useErroDoCartao';
import MolduraDoCartao from './MolduraDoCartao.vue';

// #2896, Fatia 2 — o cartão da linha que se conserta num campo de texto: o
// e-mail, o nome, ou a linha sem telefone nem e-mail (um campo só, que aceita
// os dois; quem decide qual é é o servidor). A tela só trava o campo vazio: o
// formato (o e-mail sem "@", o texto que é fórmula) quem confere é o servidor,
// e a recusa dele diz o motivo aqui mesmo.
const props = defineProps({
  problema: { type: Object, required: true },
  // 'email', 'nome' ou 'contato' (trazer/cartaoDoProblema.js).
  campo: { type: String, required: true },
  frases: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
  recusa: { type: Object, default: null },
});
const emit = defineEmits(['guardar', 'deixarDeFora']);

const { t } = useI18n();

const ROTULO = {
  email: 'RELACIONAMENTOS_TRAZER.PRECISAM.CAMPO.EMAIL',
  nome: 'RELACIONAMENTOS_TRAZER.PRECISAM.CAMPO.NOME',
  [CAMPO_CONTATO]: 'RELACIONAMENTOS_TRAZER.PRECISAM.CAMPO.CONTATO',
};
const QUE_FALTA = {
  email: 'RELACIONAMENTOS_TRAZER.PRECISAM.QUE_FALTA.EMAIL',
  nome: 'RELACIONAMENTOS_TRAZER.PRECISAM.QUE_FALTA.NOME',
};
const FALTA_O_CONTATO = 'RELACIONAMENTOS_TRAZER.PRECISAM.RECUSA.CONTATO';

const valor = ref(props.problema.valor || '');
const moldura = ref(null);
const idDoErro = useId();
const { erro, dizer } = useErroDoCartao({
  recusa: () => props.recusa,
  campo: props.campo,
  raiz: moldura,
  valor,
});

const fraseDoVazio = () =>
  props.campo === CAMPO_CONTATO
    ? t(FALTA_O_CONTATO)
    : t('RELACIONAMENTOS_TRAZER.PRECISAM.ERRO_PREENCHER', {
        campo: t(QUE_FALTA[props.campo]),
      });

// Salvar fica sempre ligado: campo vazio não salva, diz o que falta e leva o
// foco ao campo.
const guardar = () => {
  if (props.ocupado) return;
  const escrito = valor.value.trim();
  if (!escrito) {
    dizer(fraseDoVazio());
    return;
  }
  emit('guardar', props.problema.linha, escrito);
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
    <Input
      v-model="valor"
      custom-input-class="!h-11"
      :maxlength="LIMITES.VALOR"
      :aria-invalid="erro ? 'true' : undefined"
      :aria-describedby="erro ? idDoErro : undefined"
      :label="t(ROTULO[campo])"
    />
  </MolduraDoCartao>
</template>
