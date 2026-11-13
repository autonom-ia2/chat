<script setup>
// #2897 — um campo de texto (ou de data) do formulário do seguro: rótulo, o
// campo e, quando falta algo, o aviso logo embaixo. O aviso é um
// `role="alert"` com id; o campo aponta para ele (`aria-describedby`) e fica
// marcado como inválido. O id do campo vem de quem usa, que leva o foco até
// ele. A letra é a do campo da casa (components-next/input/Input.vue); a altura
// sobe para 44 px, o menor alvo de toque.
defineProps({
  id: { type: String, required: true },
  rotulo: { type: String, required: true },
  falta: { type: String, default: '' },
});

defineOptions({ inheritAttrs: false });

const texto = defineModel({ type: String, default: '' });
</script>

<template>
  <div class="flex flex-col min-w-0 gap-1.5">
    <label :for="id" class="text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </label>
    <input
      :id="id"
      v-bind="$attrs"
      v-model="texto"
      :aria-invalid="falta ? 'true' : undefined"
      :aria-describedby="falta ? `${id}-falta` : undefined"
      class="block w-full h-11 px-3 text-sm border-0 rounded-lg reset-base outline outline-1 outline-offset-[-1px] bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-n-brand"
      :class="
        falta
          ? 'outline-n-ruby-8 hover:outline-n-ruby-9'
          : 'outline-n-weak hover:outline-n-slate-6'
      "
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
