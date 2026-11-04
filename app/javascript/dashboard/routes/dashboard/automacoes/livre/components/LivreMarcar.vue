<script setup>
// #2414 F5 — escolher várias de uma lista (etiquetas, pessoas): cada opção é um
// botão de 44 px que marca e desmarca. O ChoiceSelect escolhe uma só. Opção
// bloqueada (a etiqueta já marcada em "Tirar", quando esta lista é "Pôr") fica
// à vista, mas não marca.
const props = defineProps({
  rotulo: { type: String, required: true },
  opcoes: { type: Array, required: true },
  modelValue: { type: Array, default: () => [] },
  bloqueadas: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

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
        class="inline-flex items-center gap-2 px-3 text-sm font-medium border rounded-xl min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
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
          class="size-4"
          :class="marcado(opcao.value) ? 'i-lucide-check' : 'i-lucide-plus'"
          aria-hidden="true"
        />
        {{ opcao.label }}
      </button>
    </div>
  </fieldset>
</template>
