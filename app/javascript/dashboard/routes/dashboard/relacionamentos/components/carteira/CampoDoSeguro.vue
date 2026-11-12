<script setup>
// #2897 — um campo de texto (ou de data) do formulário do seguro: rótulo, o
// campo e, quando falta algo, o aviso logo embaixo. O aviso é um
// `role="alert"` com id; o campo aponta para ele (`aria-describedby`) e fica
// marcado como inválido. O id do campo vem de quem usa, que leva o foco até ele.
// O slot `dentro` põe um botão na ponta do campo (mostrar a senha); o texto de
// apoio que fala do campo entra por `descritoPor` (o id dele, ou vários
// separados por espaço). `invalido` marca o campo quando o aviso é de quem usa
// (o login que não conferiu) e não um "falta" daqui. Altura e letra são as do
// campo da casa (components-next/input/Input.vue).
defineProps({
  id: { type: String, required: true },
  rotulo: { type: String, required: true },
  falta: { type: String, default: '' },
  descritoPor: { type: String, default: '' },
  invalido: { type: Boolean, default: false },
});

defineOptions({ inheritAttrs: false });

const texto = defineModel({ type: String, default: '' });
</script>

<template>
  <div class="flex flex-col min-w-0 gap-1.5">
    <label :for="id" class="text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </label>
    <div class="relative">
      <input
        :id="id"
        v-bind="$attrs"
        v-model="texto"
        :aria-invalid="falta || invalido ? 'true' : undefined"
        :aria-describedby="
          [falta ? `${id}-falta` : '', descritoPor].filter(Boolean).join(' ') ||
          undefined
        "
        class="block w-full h-10 px-3 text-sm border-0 rounded-lg reset-base outline outline-1 outline-offset-[-1px] bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-n-brand"
        :class="[
          falta || invalido
            ? 'outline-n-ruby-8 hover:outline-n-ruby-9'
            : 'outline-n-weak hover:outline-n-slate-6',
          $slots.dentro ? 'pe-11' : '',
        ]"
      />
      <slot name="dentro" />
    </div>
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
