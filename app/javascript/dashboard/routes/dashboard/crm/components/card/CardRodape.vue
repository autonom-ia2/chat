<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #1423 — o rodapé das telas do card: no máximo dois botões (o secundário e
// um azul), e, quando a tela pede, uma linha com o resumo ou com o que falta.
// O que cada botão faz vem de useCardMoldura.
defineProps({
  rodape: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
});
</script>

<template>
  <footer
    data-card-rodape
    class="flex flex-wrap items-center gap-2 border-t border-n-weak bg-n-solid-1 px-5 py-4 sm:px-8"
  >
    <p
      v-if="rodape.resumo"
      data-card-rodape-resumo
      class="mb-0 flex min-w-0 basis-full items-center gap-2 text-sm text-n-slate-11 sm:basis-auto"
    >
      <span
        class="i-lucide-user-round size-4 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      {{ rodape.resumo }}
    </p>
    <p
      v-if="rodape.falta"
      role="status"
      data-card-rodape-falta
      class="mb-0 flex min-w-0 basis-full items-center gap-2 text-sm text-n-amber-11 sm:basis-auto sm:flex-1"
    >
      <span class="i-lucide-info size-4 shrink-0" aria-hidden="true" />
      {{ rodape.falta }}
    </p>
    <span class="flex-1" aria-hidden="true" />
    <Button
      v-if="rodape.secundaria"
      :label="rodape.secundaria.rotulo"
      slate
      ghost
      class="!min-h-11"
      :disabled="ocupado"
      @click="rodape.secundaria.acao"
    />
    <Button
      v-if="rodape.principal"
      data-card-principal
      :type="rodape.principal.form ? 'submit' : 'button'"
      :form="rodape.principal.form"
      :label="rodape.principal.rotulo"
      :icon="rodape.principal.icone"
      :trailing-icon="Boolean(rodape.principal.depois)"
      :color="
        rodape.principal.neutro
          ? 'slate'
          : rodape.principal.perigo
            ? 'ruby'
            : 'blue'
      "
      :variant="rodape.principal.neutro ? 'faded' : 'solid'"
      class="!min-h-11 min-w-32"
      :is-loading="Boolean(rodape.principal.carregando)"
      :disabled="Boolean(rodape.principal.desabilitado)"
      @click="rodape.principal.acao?.()"
    />
  </footer>
</template>
