<script setup>
// Uma linha de Ajustes com "Alterar" (#2308, especificação 5.B2): quadrado de 40 px, nome, o que faz hoje e, quando
// mudou, a faixa de 4 px, o selo "você mudou" e o que era antes.
defineProps({
  icone: { type: String, required: true },
  tom: { type: String, required: true },
  titulo: { type: String, required: true },
  estado: { type: String, required: true },
  antes: { type: String, default: '' },
});

const emit = defineEmits(['alterar']);
</script>

<template>
  <li
    class="flex items-center gap-3 py-3 pe-3"
    :class="antes ? 'border-s-4 border-n-blue-9 ps-3' : 'ps-4'"
  >
    <span
      class="grid place-items-center size-10 shrink-0 rounded-xl"
      :class="tom"
    >
      <span class="size-5" :class="icone" aria-hidden="true" />
    </span>
    <div class="flex flex-col flex-1 min-w-0 gap-0.5">
      <p
        class="flex flex-wrap items-center gap-2 m-0 font-semibold text-n-slate-12"
      >
        {{ titulo }}
        <span
          v-if="antes"
          class="px-2 py-0.5 text-xs font-medium rounded-md bg-n-blue-3 text-n-blue-11"
        >
          {{ $t('FUNCOES_EQUIPE.GUIADA.VOCE_MUDOU') }}
        </span>
      </p>
      <p class="m-0 text-sm text-n-slate-11">
        {{ estado }}
        <template v-if="antes">
          {{ $t('FUNCOES_EQUIPE.GUIADA.ANTES_DE', { antes }) }}
        </template>
      </p>
    </div>
    <button
      type="button"
      data-alterar-area
      class="inline-flex items-center gap-2 px-4 text-sm font-medium shrink-0 rounded-xl min-h-11 bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :aria-label="$t('FUNCOES_EQUIPE.GUIADA.ALTERAR_ROTULO', { area: titulo })"
      @click="emit('alterar')"
    >
      <span class="i-lucide-pencil size-4" aria-hidden="true" />
      {{ $t('FUNCOES_EQUIPE.GUIADA.ALTERAR') }}
    </button>
  </li>
</template>
