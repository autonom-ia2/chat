<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreTexto from './LivreTexto.vue';
import {
  chaveDoModelo,
  corpoDoModelo,
  modelosDasCaixas,
  variaveisDoCorpo,
} from '../modeloWhatsapp';

// #2468 F4b — o modelo aprovado da Meta que sai quando a janela de 24 h do
// número oficial está fechada. Com a janela aberta, sai o texto acima. Cada
// variável do corpo ganha uma caixa de texto com os dados da conversa, como o
// texto livre. Os modelos vêm das caixas que a pessoa já vê no painel.
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Object, default: null },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const idModelo = useId();
const M = 'AUTOMACAO_LIVRE.ALTERAR_PAINEL.MODELO';
const NENHUM = '';

const caixas = useMapGetter('inboxes/getInboxes');
const modelos = computed(() => modelosDasCaixas(caixas.value));

const opcoes = computed(() => [
  { value: NENHUM, label: t(`${M}.NENHUM`) },
  ...modelos.value.map(modelo => ({
    value: chaveDoModelo(modelo),
    label: t(`${M}.OPCAO`, { nome: modelo.name, idioma: modelo.language }),
  })),
]);

const escolhido = computed(() =>
  modelos.value.find(
    modelo => chaveDoModelo(modelo) === chaveDoModelo(props.modelValue)
  )
);
const corpo = computed(() => corpoDoModelo(escolhido.value));
// Na ordem {{1}}, {{2}}...: a receita guarda um texto por posição.
const variaveis = computed(() =>
  [...variaveisDoCorpo(corpo.value)].sort((a, b) => Number(a) - Number(b))
);

const escolher = chave => {
  const modelo = modelos.value.find(item => chaveDoModelo(item) === chave);
  if (!modelo) {
    emit('update:modelValue', null);
    return;
  }
  const quantas = variaveisDoCorpo(corpoDoModelo(modelo)).length;
  emit('update:modelValue', {
    nome: modelo.name,
    idioma: modelo.language,
    variaveis: Array.from({ length: quantas }, () => []),
  });
};

// O modelo da caixa passou a pedir outra quantidade de variáveis depois de salvo.
const mudouVariaveis = computed(
  () =>
    escolhido.value &&
    (props.modelValue?.variaveis || []).length !== variaveis.value.length
);

// Sempre uma por variável do corpo de hoje: editar acerta o modelo que mudou.
const mudarVariavel = (indice, partes) => {
  const novas = variaveis.value.map((_, posicao) =>
    posicao === indice ? partes : props.modelValue?.variaveis?.[posicao] || []
  );
  emit('update:modelValue', { ...props.modelValue, variaveis: novas });
};
</script>

<template>
  <div class="flex flex-col gap-3" data-peca="modelo">
    <div class="flex flex-col gap-1.5">
      <label :for="idModelo" class="text-sm font-medium text-n-slate-12">
        {{ rotulo }}
      </label>
      <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${M}.DICA`) }}</p>
      <ChoiceSelect
        data-escolher-modelo
        :model-value="escolhido ? chaveDoModelo(escolhido) : NENHUM"
        :trigger-id="idModelo"
        :aria-label="rotulo"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="opcoes"
        @update:model-value="escolher"
      />
      <p
        v-if="!modelos.length"
        data-sem-modelos
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ $t(`${M}.SEM_MODELOS`) }}
      </p>
      <p
        v-else-if="modelValue && !escolhido"
        data-modelo-sumiu
        role="status"
        class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
      >
        {{ $t(`${M}.SUMIU`, { nome: modelValue.nome }) }}
      </p>
    </div>

    <template v-if="escolhido">
      <p
        v-if="escolhido.divergente"
        data-modelo-divergente
        role="status"
        class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
      >
        {{ $t(`${M}.DIVERGENTE`) }}
      </p>
      <p
        v-if="mudouVariaveis"
        data-modelo-mudou
        role="status"
        class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
      >
        {{ $t(`${M}.MUDOU`, { quantas: variaveis.length }) }}
      </p>
      <p
        data-corpo-do-modelo
        class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-alpha-1 text-n-slate-12 whitespace-pre-line"
      >
        {{ corpo }}
      </p>
      <LivreTexto
        v-for="(variavel, indice) in variaveis"
        :key="variavel"
        :rotulo="$t(`${M}.VARIAVEL`, { numero: variavel })"
        :model-value="modelValue.variaveis?.[indice] || []"
        :catalogo="catalogo"
        :atributos-do="atributosDo"
        @update:model-value="partes => mudarVariavel(indice, partes)"
      />
    </template>
  </div>
</template>
