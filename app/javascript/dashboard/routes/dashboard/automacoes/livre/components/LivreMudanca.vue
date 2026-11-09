<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { usePodeLerValor } from '../usePodeLerValor';

// G27 (#2661) — a mudança do gatilho "card atualizado": o campo do card (o
// valor de venda ou um campo personalizado), a condição (mudou, ficou igual a,
// maior que, passou de) e o valor da condição. O valor de venda só aparece para
// quem vê os valores (o servidor recusa o resto ao salvar, #2597).
const props = defineProps({
  modelValue: { type: Object, default: () => ({}) },
  // [{ value, label }]: os campos personalizados do card.
  campos: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const M = 'AUTOMACAO_LIVRE.MUDANCA';
const VALOR = 'valor';
const VALOR_DE_VENDA = 'sales_value_view';
const podeLer = usePodeLerValor();

const ATRIBUTO = 'atributo:';
const escolhido = computed(() => {
  const { campo, chave } = props.modelValue || {};
  if (campo === VALOR) return VALOR;
  return chave ? `${ATRIBUTO}${chave}` : '';
});
const opcoesDeCampo = computed(() => [
  ...(podeLer.value(VALOR_DE_VENDA) || escolhido.value === VALOR
    ? [{ value: VALOR, label: t(`${M}.VALOR_DE_VENDA`) }]
    : []),
  ...props.campos.map(item => ({
    value: `${ATRIBUTO}${item.value}`,
    label: item.label,
  })),
]);

const CONDICOES = ['mudou', 'igual', 'maior_que', 'passou_de'];
const condicoes = computed(() =>
  CONDICOES.map(valor => ({
    value: valor,
    label: t(`${M}.CONDICOES.${valor.toUpperCase()}`),
  }))
);
const pedeValor = computed(
  () => !!props.modelValue?.condicao && props.modelValue.condicao !== 'mudou'
);

// "mudou" não leva valor; o valor em branco não vai na receita.
const montar = ({ campo, chave, condicao, valor }) => ({
  campo,
  ...(campo === VALOR ? {} : { chave }),
  condicao,
  ...(condicao !== 'mudou' && valor ? { valor } : {}),
});
const mudar = parte =>
  emit('update:modelValue', montar({ ...props.modelValue, ...parte }));
const mudarCampo = valor =>
  valor === VALOR
    ? mudar({ campo: VALOR, chave: undefined })
    : mudar({ campo: 'atributo', chave: valor.slice(ATRIBUTO.length) });
</script>

<template>
  <div class="flex flex-col gap-3 ps-3 border-s-2 border-n-weak" data-mudanca>
    <div class="flex flex-col gap-1.5" data-condicao="campo">
      <span class="text-sm text-n-slate-12">{{ $t(`${M}.CAMPO`) }}</span>
      <ChoiceSelect
        :model-value="escolhido"
        :aria-label="$t(`${M}.CAMPO`)"
        :placeholder="$t(`${M}.ESCOLHA_O_CAMPO`)"
        :options="opcoesDeCampo"
        @update:model-value="mudarCampo"
      />
    </div>
    <div class="flex flex-col gap-1.5" data-condicao="condicao">
      <span class="text-sm text-n-slate-12">{{ $t(`${M}.CONDICAO`) }}</span>
      <ChoiceSelect
        :model-value="modelValue.condicao ?? ''"
        :aria-label="$t(`${M}.CONDICAO`)"
        :options="condicoes"
        @update:model-value="valor => mudar({ condicao: valor })"
      />
    </div>
    <div v-if="pedeValor" class="flex flex-col gap-1.5" data-condicao="valor">
      <span class="text-sm text-n-slate-12">{{ $t(`${M}.VALOR`) }}</span>
      <Input
        :model-value="modelValue.valor ?? ''"
        class="w-48"
        :aria-label="$t(`${M}.VALOR`)"
        :placeholder="
          $t(modelValue.campo === VALOR ? `${M}.EM_REAIS` : `${M}.VALOR`)
        "
        @update:model-value="valor => mudar({ valor: valor.trim() })"
      />
    </div>
  </div>
</template>
