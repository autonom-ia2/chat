<script setup>
import { computed, reactive, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  attributeDate,
  formatAttributeDate,
} from 'dashboard/helper/attributeDate';
import { TETO_DA_DATA, dataCompleta, opcoesDeDatas } from '../texto';
import { fraseDaData } from '../frases';

// #2414 G16b — o atributo do tipo data numa ação: um dia certo, ou uma data
// calculada na hora (a partir de hoje ou de outro campo de data, mais ou menos
// N dias, semanas, meses ou anos). Uma pergunta por vez. O dia certo vai como a
// tela da conversa grava ("AAAA-MM-DD"); a calculada vai como { $data }, e o
// "Salvar" só liga com ela inteira.
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: [String, Object], default: null },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const P = 'AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA';
const UNIDADES = ['dias', 'semanas', 'meses', 'anos'];
const ids = {
  modo: useId(),
  campo: useId(),
  unidade: useId(),
  sentido: useId(),
  quanto: useId(),
};

const modoDoValor = valor => {
  if (valor?.$data) return valor.$data.de === 'hoje' ? 'hoje' : 'campo';
  return valor ? 'dia' : '';
};
const modo = ref(modoDoValor(props.modelValue));

const data = computed(() => props.modelValue?.$data || null);
// O número fica na tela mesmo vazio ou inválido; só vai para a receita inteiro.
const escolha = reactive({
  numero: Number.isInteger(data.value?.mais?.valor)
    ? String(Math.abs(data.value.mais.valor))
    : '',
  unidade: data.value?.mais?.unidade || 'dias',
  sentido: data.value?.mais?.valor < 0 ? 'antes' : 'depois',
  campo: data.value?.de?.$valor || '',
});

const opcoesDeModo = computed(() =>
  ['dia', 'hoje', 'campo'].map(valor => ({
    value: valor,
    label: t(`${P}.${valor.toUpperCase()}`),
  }))
);
const opcoesDeCampo = computed(() =>
  opcoesDeDatas(props.catalogo, props.atributosDo, t)
);
const opcoesDeUnidade = computed(() =>
  UNIDADES.map(valor => ({
    value: valor,
    label: t(`AUTOMACAO_LIVRE.UNIDADES.${valor.toUpperCase()}`, {}, 2),
  }))
);
const opcoesDeSentido = computed(() =>
  ['depois', 'antes'].map(valor => ({
    value: valor,
    label: t(`${P}.${valor.toUpperCase()}`),
  }))
);

// "Quanto tempo?" só depois de saber de onde a data parte.
const perguntaQuanto = computed(
  () => modo.value === 'hoje' || (modo.value === 'campo' && escolha.campo)
);

const calculada = () => {
  const de =
    modo.value === 'hoje' ? 'hoje' : escolha.campo && { $valor: escolha.campo };
  const texto = escolha.numero.trim();
  const n = texto === '' ? null : Number(texto);
  if (n === 0) return { $data: { de } };
  const valido = Number.isInteger(n) && n > 0 && n <= TETO_DA_DATA;
  const valor = valido && escolha.sentido === 'antes' ? -n : n;
  return {
    $data: {
      de,
      mais: { valor: valido ? valor : null, unidade: escolha.unidade },
    },
  };
};
const avisar = () => {
  if (modo.value === 'hoje' || modo.value === 'campo')
    emit('update:modelValue', calculada());
};

const trocarModo = novo => {
  if (novo === modo.value) return;
  modo.value = novo;
  if (novo === 'dia') emit('update:modelValue', null);
  else avisar();
};
const mudar = (chave, novo) => {
  escolha[chave] = novo;
  avisar();
};

const dia = computed({
  get: () =>
    typeof props.modelValue === 'string' ? attributeDate(props.modelValue) : '',
  set: texto => emit('update:modelValue', attributeDate(texto) || null),
});

const frase = computed(() => {
  if (modo.value === 'dia')
    return dia.value ? formatAttributeDate(dia.value) : '';
  return data.value && dataCompleta(data.value)
    ? fraseDaData(
        data.value,
        props.catalogo,
        t,
        caminho =>
          opcoesDeCampo.value.find(opcao => opcao.value === caminho)?.label ??
          caminho
      )
    : '';
});
</script>

<template>
  <fieldset class="flex flex-col gap-3" data-peca="data">
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>

    <div class="flex flex-col gap-1.5">
      <label :for="ids.modo" class="text-sm text-n-slate-11">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.PERGUNTA') }}
      </label>
      <ChoiceSelect
        data-data-modo
        :model-value="modo"
        :trigger-id="ids.modo"
        :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.PERGUNTA')"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="opcoesDeModo"
        @update:model-value="trocarModo"
      />
    </div>

    <Input
      v-if="modo === 'dia'"
      v-model="dia"
      data-data-dia
      type="date"
      :label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.DIA_ROTULO')"
    />

    <div v-if="modo === 'campo'" class="flex flex-col gap-1.5">
      <label :for="ids.campo" class="text-sm text-n-slate-11">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.QUAL_CAMPO') }}
      </label>
      <ChoiceSelect
        v-if="opcoesDeCampo.length"
        data-data-campo
        :model-value="escolha.campo"
        :trigger-id="ids.campo"
        :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.QUAL_CAMPO')"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="opcoesDeCampo"
        @update:model-value="novo => mudar('campo', novo)"
      />
      <p v-else data-data-sem-campo class="mb-0 text-sm text-n-slate-11">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.SEM_CAMPO') }}
      </p>
    </div>

    <div
      v-if="perguntaQuanto"
      role="group"
      :aria-labelledby="ids.quanto"
      class="flex flex-col gap-3"
      data-data-quanto
    >
      <span :id="ids.quanto" class="text-sm text-n-slate-11">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.QUANTO') }}
      </span>
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <div class="flex flex-col gap-1.5">
          <Input
            data-data-numero
            type="number"
            min="0"
            :model-value="escolha.numero"
            :label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.NUMERO')"
            @update:model-value="novo => mudar('numero', String(novo ?? ''))"
          />
          <p data-data-zero class="mb-0 text-sm text-n-slate-11">
            {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.ZERO') }}
          </p>
        </div>
        <div class="flex flex-col gap-1.5">
          <label :for="ids.unidade" class="text-sm font-medium text-n-slate-12">
            {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.UNIDADE') }}
          </label>
          <ChoiceSelect
            data-data-unidade
            :model-value="escolha.unidade"
            :trigger-id="ids.unidade"
            :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.UNIDADE')"
            :options="opcoesDeUnidade"
            @update:model-value="novo => mudar('unidade', novo)"
          />
        </div>
        <div class="flex flex-col gap-1.5">
          <label :for="ids.sentido" class="text-sm font-medium text-n-slate-12">
            {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.SENTIDO') }}
          </label>
          <ChoiceSelect
            data-data-sentido
            :model-value="escolha.sentido"
            :trigger-id="ids.sentido"
            :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.SENTIDO')"
            :options="opcoesDeSentido"
            @update:model-value="novo => mudar('sentido', novo)"
          />
        </div>
      </div>
    </div>

    <p role="status" class="mb-0">
      <span
        v-if="frase"
        data-data-frase
        class="block px-4 py-3 text-base rounded-xl bg-n-alpha-2 text-n-slate-12"
      >
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.GRAVA', { valor: frase }) }}
      </span>
    </p>
  </fieldset>
</template>
