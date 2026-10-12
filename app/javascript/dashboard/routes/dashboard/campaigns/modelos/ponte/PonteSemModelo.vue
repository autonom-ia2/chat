<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import { usePodeCriarModelo } from '../helpers/usePodeCriarModelo';

defineProps({
  // A conta tem modelos, mas nenhum pode ir em campanha agora.
  temModelos: { type: Boolean, default: false },
  // Um recusado que dá para corrigir: { id, nome }.
  paraCorrigir: { type: Object, default: null },
});
const emit = defineEmits(['criar', 'corrigir']);
// Caixa sem modelo para usar: uma frase e a saída (criar ou corrigir), sem
// perder a campanha (o rascunho fica guardado e volta com o modelo novo
// escolhido). Quem não pode criar modelo vê só a frase.
const podeCriar = usePodeCriarModelo();
</script>

<template>
  <div
    data-ponte-sem-modelo
    class="flex flex-col items-start gap-3 p-4 rounded-xl bg-n-slate-2"
  >
    <p class="mb-0 text-sm text-n-slate-12">
      {{
        temModelos
          ? $t('MODELOS_WHATSAPP.PONTE.SEM_MODELO_LIBERADO')
          : $t('MODELOS_WHATSAPP.PONTE.SEM_MODELO')
      }}
    </p>
    <div v-if="podeCriar" class="flex flex-wrap gap-2">
      <Button
        data-criar-modelo
        :label="$t('MODELOS_WHATSAPP.ACOES.CRIAR')"
        icon="i-lucide-plus"
        class="!min-h-11 !rounded-xl"
        @click="emit('criar')"
      />
      <Button
        v-if="paraCorrigir"
        data-corrigir-modelo
        :label="
          $t('MODELOS_WHATSAPP.PONTE.CORRIGIR', { nome: paraCorrigir.nome })
        "
        icon="i-lucide-wrench"
        color="slate"
        variant="faded"
        class="!min-h-11 !rounded-xl"
        @click="emit('corrigir', paraCorrigir.id)"
      />
    </div>
  </div>
</template>
