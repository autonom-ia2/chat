<script setup>
// chat#1487 — cabeçalho escuro da aba WhatsApp API, com a anatomia dos heróis do fork (funil #1384, passagem
// #1385, Nova conversa #1459): anéis, rótulo com ícone, título que diz o benefício e uma frase. Sem migalha e sem
// X: é uma aba das configurações da caixa, e o cabeçalho da página já diz onde a pessoa está. O selo diz o estado.
import { computed } from 'vue';
import { STATUS_VISUALS } from '../whatsappHybridState';

const props = defineProps({
  statusKey: { type: String, default: '' },
  statusLabel: { type: String, default: '' },
});

const visual = computed(() => STATUS_VISUALS[props.statusKey]);
</script>

<template>
  <header
    data-hybrid-heroi
    class="relative overflow-hidden rounded-2xl bg-[#0D2344] px-5 py-6 text-white sm:px-8"
  >
    <span
      aria-hidden="true"
      class="pointer-events-none absolute -end-16 -top-24 size-80 rounded-full border-[3rem] border-n-blue-9 opacity-15"
    />
    <span
      aria-hidden="true"
      class="pointer-events-none absolute -bottom-36 end-32 size-56 rounded-full border-[2rem] border-n-blue-7 opacity-10"
    />
    <div class="relative flex flex-col gap-1.5">
      <span
        class="inline-flex items-center gap-2 text-sm font-semibold text-n-blue-6 dark:text-n-blue-11"
      >
        <span class="i-ri-whatsapp-line size-4" aria-hidden="true" />
        {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.TITLE') }}
      </span>
      <h2
        class="mb-0 text-2xl font-bold leading-tight tracking-tight text-white break-words"
      >
        {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.HERO.TITLE') }}
      </h2>
      <p class="mb-0 text-sm leading-relaxed text-white/75 sm:text-base">
        {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.HERO.TEXT') }}
      </p>
      <span
        v-if="visual && statusLabel"
        data-hybrid-selo
        role="status"
        class="inline-flex items-center gap-1.5 px-2.5 py-1 mt-2 text-sm font-medium rounded-full w-fit whitespace-nowrap"
        :class="visual.chip"
      >
        <span class="size-4" :class="visual.icon" aria-hidden="true" />
        {{ statusLabel }}
      </span>
    </div>
  </header>
</template>
