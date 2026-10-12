<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import { usePodeCriarModelo } from '../helpers/usePodeCriarModelo';

const emit = defineEmits(['criar']);
// Caixa sem modelo para usar: uma frase e o botão para criar, sem perder a
// campanha (o rascunho fica guardado e volta com o modelo novo escolhido).
// Quem não pode criar modelo vê só a frase.
const podeCriar = usePodeCriarModelo();
</script>

<template>
  <div
    data-ponte-sem-modelo
    class="flex flex-col items-start gap-3 p-4 rounded-xl bg-n-slate-2"
  >
    <p class="mb-0 text-sm text-n-slate-12">
      {{ $t('MODELOS_WHATSAPP.PONTE.SEM_MODELO') }}
    </p>
    <Button
      v-if="podeCriar"
      data-criar-modelo
      :label="$t('MODELOS_WHATSAPP.ACOES.CRIAR')"
      icon="i-lucide-plus"
      class="!min-h-11 !rounded-xl"
      @click="emit('criar')"
    />
  </div>
</template>
