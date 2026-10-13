<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #1384 — a frase sugerida lado a lado com a de hoje ("Como está" → "Como
// fica"). Nada troca até a pessoa escolher.
const props = defineProps({
  antes: { type: String, default: '' },
  depois: { type: String, required: true },
  nota: { type: String, default: '' },
});

defineEmits(['usar', 'manter']);

const temAntes = computed(() => props.antes.trim() !== '');
</script>

<template>
  <section
    data-funil-sugestao
    aria-live="polite"
    class="flex flex-col gap-4 rounded-2xl border border-n-blue-7 bg-n-blue-2 p-5"
  >
    <header class="flex flex-wrap items-baseline justify-between gap-2">
      <h4
        class="mb-0 flex items-center gap-2 text-base font-semibold text-n-slate-12"
      >
        <span
          class="i-lucide-sparkles size-4 text-n-blue-11"
          aria-hidden="true"
        />
        {{ $t('CRM_FUNIL.ETAPA.SUGESTAO') }}
      </h4>
      <span class="text-sm text-n-slate-11">
        {{ $t('CRM_FUNIL.ETAPA.NADA_MUDA') }}
      </span>
    </header>
    <div class="grid gap-3" :class="temAntes ? 'md:grid-cols-2' : ''">
      <div
        v-if="temAntes"
        class="flex flex-col gap-2 rounded-xl border border-n-weak bg-n-solid-1 p-4"
      >
        <span class="text-sm font-medium text-n-slate-11">
          {{ $t('CRM_FUNIL.ETAPA.COMO_ESTA') }}
        </span>
        <p
          class="mb-0 whitespace-pre-wrap text-[0.9375rem] leading-relaxed text-n-slate-11"
        >
          {{ antes }}
        </p>
      </div>
      <div
        class="flex flex-col gap-2 rounded-xl border-2 border-n-blue-8 bg-n-solid-1 p-4"
      >
        <span class="text-sm font-semibold text-n-blue-11">
          {{ $t('CRM_FUNIL.ETAPA.COMO_FICA') }}
        </span>
        <p
          class="mb-0 whitespace-pre-wrap text-[0.9375rem] leading-relaxed text-n-slate-12"
        >
          {{ depois }}
        </p>
      </div>
    </div>
    <p v-if="nota" class="mb-0 text-sm text-n-slate-11">{{ nota }}</p>
    <div class="flex flex-wrap gap-2">
      <Button
        data-usar-sugestao
        :label="$t('CRM_FUNIL.ETAPA.USAR')"
        icon="i-lucide-check"
        blue
        faded
        class="!min-h-11"
        @click="$emit('usar')"
      />
      <Button
        :label="
          $t(temAntes ? 'CRM_FUNIL.ETAPA.MANTER' : 'CRM_FUNIL.ETAPA.DESCARTAR')
        "
        slate
        ghost
        class="!min-h-11"
        @click="$emit('manter')"
      />
    </div>
  </section>
</template>
