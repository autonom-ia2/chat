<script setup>
import { computed, useId } from 'vue';

const props = defineProps({
  rotulo: { type: String, required: true },
  erro: { type: String, default: '' },
  // #3075 — uma linha de ajuda embaixo do campo (o que acontece ao salvar).
  ajuda: { type: String, default: '' },
  // #3075 — texto longo ("Sobre a pessoa"): uma caixa com várias linhas.
  linhas: { type: Number, default: 0 },
});

// #2894 — campo de texto da gaveta: rótulo, o campo e a mensagem de erro embaixo
// (anunciada ao leitor de tela). Existe porque o `Input` da casa repassa os
// atributos soltos também para a caixa de fora, e o foco da gaveta
// (`data-foco`) precisa estar só no campo de verdade. Mesmo visual do `Input`,
// com 44 px de altura (o menor alvo de toque).
defineOptions({ inheritAttrs: false });

const texto = defineModel({ type: String, default: '' });
const id = useId();
const idDoErro = `${id}-erro`;
const idDaAjuda = `${id}-ajuda`;
const descrito = computed(
  () =>
    [props.erro && idDoErro, props.ajuda && idDaAjuda]
      .filter(Boolean)
      .join(' ') || undefined
);
const contorno = computed(() =>
  props.erro
    ? 'outline-n-ruby-8 hover:outline-n-ruby-9'
    : 'outline-n-weak hover:outline-n-slate-6'
);
</script>

<template>
  <div class="flex flex-col min-w-0">
    <div class="flex items-center justify-between min-w-0 gap-3 mb-1.5">
      <label
        :for="id"
        class="min-w-0 break-words text-heading-3 text-n-slate-12"
      >
        {{ rotulo }}
      </label>
      <!-- #3075 — uma ação do campo ao lado do rótulo ("Apagar"). -->
      <slot name="acao" />
    </div>
    <textarea
      v-if="linhas"
      :id="id"
      v-bind="$attrs"
      v-model="texto"
      :rows="linhas"
      :aria-invalid="erro ? 'true' : undefined"
      :aria-describedby="descrito"
      class="block w-full px-3 py-2.5 text-sm leading-6 border-0 rounded-lg resize-y min-h-24 reset-base outline outline-1 outline-offset-[-1px] bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-n-brand"
      :class="contorno"
    />
    <input
      v-else
      :id="id"
      v-bind="$attrs"
      v-model="texto"
      :aria-invalid="erro ? 'true' : undefined"
      :aria-describedby="descrito"
      class="block w-full h-11 px-3 py-2.5 text-sm border-0 rounded-lg reset-base outline outline-1 outline-offset-[-1px] bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-n-brand"
      :class="contorno"
    />
    <p
      v-if="ajuda"
      :id="idDaAjuda"
      class="mt-2 mb-0 text-sm text-n-slate-11"
      data-relacionamentos="ajuda-do-campo"
    >
      {{ ajuda }}
    </p>
    <!-- Região viva fixa: nasce vazia e recebe o texto do erro depois. -->
    <p
      :id="idDoErro"
      aria-live="polite"
      class="min-w-0 mb-0 text-sm text-n-ruby-9 break-words"
      :class="erro ? 'mt-2' : 'mt-0'"
    >
      {{ erro }}
    </p>
  </div>
</template>
