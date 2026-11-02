<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { fraseDaCondicao, opcoesDoValor } from '../frases';

// #2414 F5 — uma condição: o que olhar, como comparar e com o quê. O que olhar
// sai do catálogo (os valores que o motor lê) e, para campo personalizado, dos
// campos que a conta tem. Condição com várias partes (todas/alguma), que só o
// Guia monta, aparece em frase e passa intacta.
const props = defineProps({
  // Sem rótulo quando o painel inteiro é a condição (o título já diz).
  rotulo: { type: String, default: '' },
  modelValue: { type: Object, default: null },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const idCampo = useId();
const idOp = useId();
const idValor = useId();

const composta = computed(() =>
  Boolean(props.modelValue?.todas || props.modelValue?.alguma)
);

const opcoesDeCampo = computed(() =>
  props.catalogo.valores.flatMap(item => {
    if (!item.atributos) return [{ value: item.caminho, label: t(item.frase) }];
    return props.atributosDo(item.atributos).map(atributo => ({
      value: `${item.caminho}.${atributo.attribute_key}`,
      label: t('AUTOMACAO_LIVRE.FRASES.ATRIBUTO', {
        base: t(item.frase),
        chave: atributo.attribute_display_name,
      }),
    }));
  })
);

const opcoesDeOp = computed(() =>
  props.catalogo.operadores.map(item => ({
    value: item.op,
    label: t(item.frase),
  }))
);
const operador = computed(() =>
  props.catalogo.operadores.find(item => item.op === props.modelValue?.op)
);

// "Maior" e "menor" comparam número: o texto vira número quando é um.
const NUMERICOS = ['maior', 'menor'];
const lerValor = (op, texto) =>
  NUMERICOS.includes(op) && texto !== '' && Number.isFinite(Number(texto))
    ? Number(texto)
    : texto;

const montar = ({ campo, op, valor }) => {
  const condicao = { campo: { $valor: campo }, op };
  const pedeValor = props.catalogo.operadores.find(
    item => item.op === op
  )?.pede_valor;
  return pedeValor
    ? { ...condicao, valor: lerValor(op, valor ?? '') }
    : condicao;
};

const atual = computed(() => ({
  campo: props.modelValue?.campo?.$valor || '',
  op: props.modelValue?.op || 'igual',
  valor: props.modelValue?.valor ?? '',
}));

const opcoesDeValor = computed(() =>
  (opcoesDoValor(atual.value.campo, props.catalogo) || []).map(item => ({
    value: item.valor,
    label: t(item.frase),
  }))
);

const mudar = (chave, novo) =>
  emit('update:modelValue', montar({ ...atual.value, [chave]: novo }));
</script>

<template>
  <fieldset class="flex flex-col gap-3" data-peca="condicao">
    <legend v-if="rotulo" class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <template v-if="composta">
      <p
        class="px-4 py-3 mb-0 text-base rounded-xl bg-n-alpha-2 text-n-slate-12"
      >
        {{ fraseDaCondicao(modelValue, catalogo, t) }}
      </p>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.COMPOSTA') }}
      </p>
    </template>
    <template v-else>
      <div class="flex flex-col gap-1.5">
        <label :for="idCampo" class="text-sm text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CAMPO') }}
        </label>
        <ChoiceSelect
          :model-value="atual.campo"
          :trigger-id="idCampo"
          :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CAMPO')"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="opcoesDeCampo"
          @update:model-value="novo => mudar('campo', novo)"
        />
      </div>
      <div class="flex flex-col gap-1.5">
        <label :for="idOp" class="text-sm text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.OPERADOR') }}
        </label>
        <ChoiceSelect
          :model-value="atual.op"
          :trigger-id="idOp"
          :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.OPERADOR')"
          :options="opcoesDeOp"
          @update:model-value="novo => mudar('op', novo)"
        />
      </div>
      <div
        v-if="operador?.pede_valor && opcoesDeValor.length"
        class="flex flex-col gap-1.5"
      >
        <label :for="idValor" class="text-sm text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.VALOR') }}
        </label>
        <ChoiceSelect
          data-valor-condicao
          :model-value="atual.valor"
          :trigger-id="idValor"
          :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.VALOR')"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="opcoesDeValor"
          @update:model-value="novo => mudar('valor', novo)"
        />
      </div>
      <Input
        v-else-if="operador?.pede_valor"
        data-valor-condicao
        :model-value="String(atual.valor)"
        :label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.VALOR')"
        @update:model-value="novo => mudar('valor', novo)"
      />
    </template>
  </fieldset>
</template>
