<script setup>
import { useId } from 'vue';

defineProps({
  rotulo: { type: String, required: true },
  erro: { type: String, default: '' },
});

// #2894 — campo de texto da gaveta: rótulo, o campo e a mensagem de erro embaixo
// (anunciada ao leitor de tela). Existe porque o `Input` da casa repassa os
// atributos soltos também para a caixa de fora, e o foco da gaveta
// (`data-foco`) precisa estar só no campo de verdade. Mesmo visual do `Input`.
defineOptions({ inheritAttrs: false });

const texto = defineModel({ type: String, default: '' });
const id = useId();
const idDoErro = `${id}-erro`;
</script>

<template>
  <div class="flex flex-col min-w-0">
    <label :for="id" class="mb-1.5 text-heading-3 text-n-slate-12">
      {{ rotulo }}
    </label>
    <input
      :id="id"
      v-bind="$attrs"
      v-model="texto"
      :aria-invalid="erro ? 'true' : undefined"
      :aria-describedby="erro ? idDoErro : undefined"
      class="block w-full h-10 px-3 py-2.5 text-sm border-0 rounded-lg reset-base outline outline-1 outline-offset-[-1px] bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-n-brand"
      :class="
        erro
          ? 'outline-n-ruby-8 hover:outline-n-ruby-9'
          : 'outline-n-weak hover:outline-n-slate-6'
      "
    />
    <!-- Região viva fixa: nasce vazia e recebe o texto do erro depois. -->
    <p
      :id="idDoErro"
      aria-live="polite"
      class="min-w-0 mb-0 text-label-small text-n-ruby-9 break-words"
      :class="erro ? 'mt-2' : 'mt-0'"
    >
      {{ erro }}
    </p>
  </div>
</template>
