<script setup>
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #2897 — uma escolha única do formulário do seguro (par do CampoDoSeguro, que
// é o de texto): rótulo, a lista da casa (nunca o <select> do navegador) e,
// quando falta escolher, o aviso logo embaixo. O aviso é um `role="alert"` com
// id; o botão da lista aponta para ele e fica marcado como inválido. O id do
// botão vem de quem usa, que leva o foco até ele. Sem escolha, o botão mostra
// `vazio` ("Escolha").
//   opcoes: [{ value, label }]    v-model: o `value` escolhido ('' = nenhum)
defineProps({
  id: { type: String, required: true },
  rotulo: { type: String, required: true },
  opcoes: { type: Array, required: true },
  vazio: { type: String, required: true },
  falta: { type: String, default: '' },
});

const escolha = defineModel({ type: String, default: '' });
</script>

<template>
  <div class="flex flex-col min-w-0 gap-1.5">
    <label :for="id" class="text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </label>
    <ChoiceSelect
      v-model="escolha"
      class="w-full"
      :trigger-id="id"
      :options="opcoes"
      :aria-label="rotulo"
      :placeholder="vazio"
      :invalid="Boolean(falta)"
      :described-by="falta ? `${id}-falta` : undefined"
    />
    <p
      v-if="falta"
      :id="`${id}-falta`"
      role="alert"
      data-carteira="falta"
      class="m-0 text-sm break-words text-n-ruby-11"
    >
      {{ falta }}
    </p>
  </div>
</template>
