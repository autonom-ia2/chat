<script setup>
import { computed, useId } from 'vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #2414 F5 — escolher várias de uma lista (etiquetas, pessoas): cada opção é um
// botão de 44 px que marca e desmarca. O ChoiceSelect escolhe uma só. Opção
// bloqueada (a etiqueta já marcada em "Tirar", quando esta lista é "Pôr") fica
// à vista, mas não marca.
// #2702 G29 — com `dados` (o "Pôr" etiqueta), a lista também leva um dado: a
// etiqueta sai com o nome que ele tiver na hora ("o anúncio do formulário").
// Na receita vai `{ $valor }`; a pessoa vê o nome do dado entre colchetes.
const props = defineProps({
  rotulo: { type: String, required: true },
  opcoes: { type: Array, required: true },
  modelValue: { type: Array, default: () => [] },
  bloqueadas: { type: Array, default: () => [] },
  dados: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);
const idDado = useId();

const doDado = item => Boolean(item?.$valor);
const postos = computed(() => (props.modelValue || []).filter(doDado));
const nomeDoDado = caminho =>
  `[${props.dados.find(dado => dado.value === caminho)?.label || caminho}]`;
const dadosLivres = computed(() =>
  props.dados.filter(
    dado => !postos.value.some(item => item.$valor === dado.value)
  )
);
const porDado = caminho =>
  caminho &&
  emit('update:modelValue', [...(props.modelValue || []), { $valor: caminho }]);
const tirarDado = caminho =>
  emit(
    'update:modelValue',
    (props.modelValue || []).filter(item => item?.$valor !== caminho)
  );

const marcado = valor => (props.modelValue || []).includes(valor);
const bloqueada = valor => props.bloqueadas.includes(valor);
const alternar = valor =>
  !bloqueada(valor) &&
  emit(
    'update:modelValue',
    marcado(valor)
      ? props.modelValue.filter(item => item !== valor)
      : [...(props.modelValue || []), valor]
  );
</script>

<template>
  <fieldset class="flex flex-col gap-2" data-peca="marcar">
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <div class="flex flex-wrap gap-2">
      <button
        v-for="opcao in opcoes"
        :key="opcao.value"
        type="button"
        :aria-pressed="marcado(opcao.value)"
        :aria-disabled="bloqueada(opcao.value) || undefined"
        class="inline-flex items-center gap-2 px-3 text-sm font-medium border text-start rounded-xl min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="{
          'border-n-blue-8 bg-n-blue-3 text-n-blue-11': marcado(opcao.value),
          'border-n-weak bg-n-solid-1 text-n-slate-11':
            !marcado(opcao.value) && !bloqueada(opcao.value),
          'border-n-weak bg-n-alpha-1 text-n-slate-9 cursor-not-allowed':
            bloqueada(opcao.value),
        }"
        @click="alternar(opcao.value)"
      >
        <span
          class="size-4 shrink-0"
          :class="marcado(opcao.value) ? 'i-lucide-check' : 'i-lucide-plus'"
          aria-hidden="true"
        />
        {{ opcao.label }}
      </button>
      <button
        v-for="item in postos"
        :key="item.$valor"
        type="button"
        data-dado-posto
        aria-pressed="true"
        class="inline-flex items-center gap-2 px-3 text-sm font-medium border text-start rounded-xl min-h-11 border-n-blue-8 bg-n-blue-3 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="tirarDado(item.$valor)"
      >
        <span class="size-4 shrink-0 i-lucide-check" aria-hidden="true" />
        {{ nomeDoDado(item.$valor) }}
      </button>
    </div>
    <div v-if="dados.length" data-por-dado class="flex flex-col gap-1.5 mt-1">
      <label :for="idDado" class="text-sm font-medium text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_DADO_NA_ETIQUETA') }}
      </label>
      <ChoiceSelect
        model-value=""
        :trigger-id="idDado"
        :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_DADO_NA_ETIQUETA')"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="dadosLivres"
        @update:model-value="porDado"
      />
    </div>
  </fieldset>
</template>
