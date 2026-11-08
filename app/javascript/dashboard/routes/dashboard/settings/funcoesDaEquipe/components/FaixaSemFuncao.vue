<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// Quem está sem função vê MAIS, não menos (#2308): a faixa diz isso e leva às pessoas. No celular, a frase curta.
defineProps({
  quantidade: { type: Number, required: true },
});

const emit = defineEmits(['verQuemSao']);
</script>

<template>
  <div
    data-faixa-sem-funcao
    role="status"
    class="flex items-center gap-3 px-4 py-3 rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak sm:gap-4 sm:p-4"
  >
    <span
      class="hidden sm:grid place-items-center size-10 shrink-0 rounded-xl bg-n-alpha-2 text-n-slate-11"
    >
      <span class="i-lucide-users size-5" aria-hidden="true" />
    </span>
    <p class="flex-1 m-0 text-[0.9375rem] text-n-slate-12">
      <span class="hidden sm:inline">
        <span class="font-semibold">
          {{ $t('FUNCOES_EQUIPE.FAIXA.TITULO', { n: quantidade }, quantidade) }}
        </span>
        {{ $t('FUNCOES_EQUIPE.FAIXA.TEXTO', quantidade) }}
      </span>
      <span class="sm:hidden">
        <span class="font-semibold">
          {{
            $t(
              'FUNCOES_EQUIPE.FAIXA.TITULO_CURTO',
              { n: quantidade },
              quantidade
            )
          }}
        </span>
        {{ $t('FUNCOES_EQUIPE.FAIXA.TEXTO_CURTO', quantidade) }}
      </span>
    </p>
    <Button
      data-ver-quem-sao
      :label="$t('FUNCOES_EQUIPE.FAIXA.VER_QUEM_SAO')"
      slate
      faded
      class="min-h-11 shrink-0"
      @click="emit('verQuemSao')"
    />
  </div>
</template>
