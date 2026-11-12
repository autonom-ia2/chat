<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #2692 — o rodapé fixo das páginas com o botão principal (molde
// CampaignJourney/AudienceSearchReview.vue).
// Rodada 2:
// - sempre colado embaixo: `mt-auto` numa página `min-h-full flex-col`;
// - fundo da página de borda a borda, para nada da lista aparecer pelos lados;
// - em 390 o botão redondo do menu fica na faixa que o layout reserva embaixo
//   (#2477, Dashboard.vue): a página termina acima dele, e o rodapé usa a
//   largura inteira;
// - o motivo de o botão estar desligado vai numa linha acima dele (`dica`),
//   nunca dentro do botão: o botão diz sempre a ação.
defineProps({
  rotulo: { type: String, required: true },
  desabilitado: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
  icone: { type: String, default: '' },
  dica: { type: String, default: '' },
  secundario: { type: Boolean, default: false },
});
const emit = defineEmits(['principal']);
</script>

<template>
  <footer
    class="sticky bottom-0 z-10 px-4 py-3 mt-auto -mx-4 border-t border-n-weak bg-n-surface-1 md:-mx-8 md:px-8 md:py-4"
    data-rodape
  >
    <div
      class="flex flex-col gap-2 md:flex-row md:items-center md:justify-end md:gap-4"
    >
      <div v-if="$slots.default || dica" class="min-w-0 md:flex-1">
        <p
          v-if="dica"
          class="m-0 text-sm text-n-slate-11 md:text-end"
          role="status"
          data-dica
        >
          {{ dica }}
        </p>
        <slot />
      </div>
      <Button
        :label="rotulo"
        :icon="icone"
        :disabled="desabilitado"
        :is-loading="ocupado"
        :slate="secundario"
        :faded="secundario"
        class="!h-auto !min-h-12 !whitespace-normal !rounded-xl !px-6 !py-2 !text-base md:min-w-[14rem]"
        data-principal
        @click="emit('principal')"
      />
    </div>
  </footer>
</template>
