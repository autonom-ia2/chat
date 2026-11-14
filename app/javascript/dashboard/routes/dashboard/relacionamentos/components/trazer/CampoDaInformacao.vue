<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { campoDaColuna } from '../../trazer/destinos';
import { LIMITES } from '../../trazer/limites';

// #2896 — a coluna que vira "informação nova" é guardada como um campo novo da
// pessoa: o nome dele (já vem com o título da coluna) e o "Para que serve?"
// (opcional, uma linha). Salvar campo sai como evento, com o campo no formato do
// servidor (`{ nome, para_que_serve }`); quem escreve é a linha da coluna.
// Nada de botão desligado: sem nome, o clique diz o que falta e leva o foco ao
// campo. `pendente`: a coluna ainda não é informação nova (a pessoa escolheu
// esse destino numa coluna sem título), então salvar escreve mesmo sem mudança.
// Os dois campos e o Salvar têm 44 px de altura (alvo de toque).
const props = defineProps({
  coluna: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
  pendente: { type: Boolean, default: false },
});
const emit = defineEmits(['salvar']);

const { t } = useI18n();
const id = useId();
const formulario = ref(null);

const guardado = computed(() => campoDaColuna(props.coluna));
const nome = ref(guardado.value.nome);
const paraQueServe = ref(guardado.value.para_que_serve);
const erro = ref('');
const salvo = ref(false);
// Esta linha mandou salvar e ainda não soube como terminou.
let enviou = false;

const escrito = () => ({
  nome: nome.value.trim(),
  para_que_serve: paraQueServe.value.trim(),
});
const mudou = () => {
  const campo = escrito();
  return (
    props.pendente ||
    campo.nome !== guardado.value.nome ||
    campo.para_que_serve !== guardado.value.para_que_serve
  );
};

// O servidor devolveu outro campo: os dois campos passam a mostrar o que está
// guardado. Outra coluna que muda não mexe no que a pessoa está escrevendo aqui.
watch(
  [() => guardado.value.nome, () => guardado.value.para_que_serve],
  ([nomeGuardado, paraQueServeGuardado]) => {
    nome.value = nomeGuardado;
    paraQueServe.value = paraQueServeGuardado;
  }
);

// A escrita terminou: só diz "Salvo" se o servidor ficou com o que está aqui.
watch(
  () => props.ocupado,
  ocupado => {
    if (ocupado || !enviou) return;
    enviou = false;
    salvo.value = !mudou();
  }
);

const mexeu = () => {
  erro.value = '';
  salvo.value = false;
};

const focarNome = () => formulario.value?.querySelector('input')?.focus();

const salvar = () => {
  if (props.ocupado) return;
  const campo = escrito();
  if (!campo.nome) {
    erro.value = t('RELACIONAMENTOS_TRAZER.GUARDAR.ERRO_NOME_DO_CAMPO');
    focarNome();
    return;
  }
  if (!mudou()) {
    salvo.value = true;
    return;
  }
  enviou = true;
  salvo.value = false;
  emit('salvar', campo);
};

defineExpose({ focarNome });
</script>

<template>
  <form
    ref="formulario"
    data-relacionamentos="campo-da-informacao"
    class="flex flex-col w-full max-w-md gap-3"
    novalidate
    @submit.prevent="salvar"
  >
    <Input
      v-model="nome"
      data-campo="nome"
      custom-input-class="!h-11"
      :maxlength="LIMITES.NOME_DO_CAMPO"
      :label="t('RELACIONAMENTOS_TRAZER.GUARDAR.CAMPO_NOME')"
      :aria-invalid="erro ? 'true' : undefined"
      :aria-describedby="erro ? `${id}-erro` : undefined"
      @input="mexeu"
    />
    <Input
      v-model="paraQueServe"
      data-campo="para-que-serve"
      custom-input-class="!h-11"
      :maxlength="LIMITES.PARA_QUE_SERVE"
      :label="t('RELACIONAMENTOS_TRAZER.GUARDAR.CAMPO_PARA_QUE_SERVE')"
      :message="t('RELACIONAMENTOS_TRAZER.GUARDAR.AJUDA_PARA_QUE_SERVE')"
      wrap-message
      @input="mexeu"
    />
    <p
      v-if="erro"
      :id="`${id}-erro`"
      data-relacionamentos="erro-do-campo"
      role="alert"
      class="m-0 text-sm font-medium text-n-ruby-11"
    >
      {{ erro }}
    </p>
    <div class="flex flex-wrap items-center gap-3">
      <Button
        type="submit"
        faded
        slate
        class="min-h-11"
        :label="t('RELACIONAMENTOS_TRAZER.GUARDAR.SALVAR_CAMPO')"
        :disabled="ocupado"
      />
      <p role="status" class="m-0 text-sm text-n-slate-11">
        {{ salvo ? t('RELACIONAMENTOS_TRAZER.GUARDAR.SALVO') : '' }}
      </p>
    </div>
  </form>
</template>
