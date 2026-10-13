<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  camposDoModelo,
  comCampo,
  modeloCompleto,
  paramsVazios,
  payloadDoModelo,
  previaDoModelo,
  trechoFalado,
  SINAIS,
} from './modeloPronto';

// #1459 — "Complete a mensagem": um campo por parte variável da mensagem
// pronta. O rótulo é o trecho da própria mensagem em volta do campo, com a
// pastilha no lugar dele, e o placeholder é o exemplo do próprio modelo. Todo
// campo começa vazio. Expõe a mesma interface do preenchedor antigo (isFormInvalid, renderedHeader, renderedTemplate,
// sendMessage), e o que envia tem o mesmo formato.
const props = defineProps({
  template: { type: Object, required: true },
});

const emit = defineEmits(['sendMessage']);

const { t } = useI18n();
const P = 'NOVA_CONVERSA.MENSAGEM';

const params = ref({});
const campos = computed(() => camposDoModelo(props.template));
const previa = computed(() => previaDoModelo(props.template, params.value));
const isFormInvalid = computed(
  () => !modeloCompleto(props.template, params.value)
);
const renderedHeader = computed(() => previa.value.cabecalho);
const renderedTemplate = computed(() => previa.value.corpo);

watch(
  () => props.template,
  modelo => {
    params.value = paramsVazios(modelo);
  },
  { immediate: true }
);

// Mensagem que é só o campo não tem trecho em volta: vale a frase genérica.
const temTrecho = campo => campo.trecho.some(parte => parte.texto?.trim());
const falado = campo =>
  temTrecho(campo)
    ? trechoFalado(campo.trecho, chave =>
        t(`${P}.CAMPO_FALADO`, { campo: chave })
      )
    : t(`${P}.CAMPO_ROTULO`, { campo: campo.chave });

const valorDe = campo => params.value[campo.parte]?.[campo.chave] || '';
const mudar = (campo, valor) => {
  params.value = comCampo(params.value, campo, valor);
};

const sendMessage = () => {
  if (isFormInvalid.value) return;
  emit('sendMessage', payloadDoModelo(props.template, params.value));
};

defineExpose({ isFormInvalid, renderedHeader, renderedTemplate, sendMessage });
</script>

<template>
  <!-- Modelo sem campo não desenha nada, mas o componente continua montado:
       é ele quem entrega a mensagem pronta na hora de enviar. -->
  <fieldset
    v-show="campos.length"
    data-nova-conversa-campos
    class="m-0 flex min-w-0 flex-col gap-4 border-0 p-0"
  >
    <legend class="mb-4 p-0 text-base font-semibold text-n-slate-12">
      {{ $t(`${P}.COMPLETE`) }}
    </legend>
    <div
      v-for="(campo, indice) in campos"
      :key="`${campo.parte}-${campo.chave}`"
      class="flex flex-col gap-2"
    >
      <label
        :for="`nova-conversa-campo-${campo.parte}-${campo.chave}`"
        class="mb-0 text-[0.9375rem] font-medium text-n-slate-12"
      >
        <template v-if="temTrecho(campo)">
          <span aria-hidden="true">{{ SINAIS.abreAspas }}</span>
          <template v-for="(parte, posicao) in campo.trecho" :key="posicao">
            <span
              v-if="parte.campo"
              :data-campo-alvo="parte.alvo ? '' : null"
              class="mx-0.5 inline-block rounded-md px-1.5 align-baseline text-xs font-semibold leading-5"
              :class="
                parte.alvo
                  ? 'bg-n-blue-3 text-n-blue-11'
                  : 'bg-n-alpha-2 text-n-slate-11'
              "
            >
              {{ SINAIS.reticencias }}
            </span>
            <template v-else>{{ parte.texto }}</template>
          </template>
          <span aria-hidden="true">{{ SINAIS.fechaAspas }}</span>
        </template>
        <template v-else>
          {{ $t(`${P}.CAMPO_ROTULO`, { campo: campo.chave }) }}
        </template>
      </label>
      <input
        :id="`nova-conversa-campo-${campo.parte}-${campo.chave}`"
        :data-foco="indice === 0 ? '' : null"
        :aria-label="falado(campo)"
        type="text"
        autocomplete="off"
        :value="valorDe(campo)"
        :placeholder="
          campo.exemplo
            ? $t(`${P}.CAMPO_EXEMPLO`, { exemplo: campo.exemplo })
            : ''
        "
        class="reset-base !mb-0 min-h-11 w-full rounded-2xl border border-n-weak bg-n-solid-1 px-4 text-base text-n-slate-12 outline-none transition placeholder:text-n-slate-10 hover:border-n-slate-7 focus:border-n-blue-8 focus:shadow-md"
        @input="mudar(campo, $event.target.value)"
      />
    </div>
  </fieldset>
</template>
