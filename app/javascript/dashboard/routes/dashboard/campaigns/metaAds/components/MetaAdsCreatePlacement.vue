<script setup>
import { computed, ref } from 'vue';

// Anúncios da Meta (#2198): onde o anúncio aparece, na conferência. Automático (recomendado) já vem marcado: vai
// para a Meta como publisher_platforms ["facebook", "instagram"] sem posição, e ela escolhe feed, Stories ou Reels.
// "Só Instagram" e "Só Facebook" mandam uma plataforma. Só aparecem os lugares que a chamada real já confirmou para
// o destino (`placements_by_destination` das opções); com um lugar só, não há "Trocar". Post impulsionado do Facebook
// não troca: roda no Facebook (#2339).
const props = defineProps({
  // Lugares confirmados, na ordem da tela.
  options: { type: Array, default: () => ['AUTO', 'INSTAGRAM', 'FACEBOOK'] },
  // Post da Página: sem escolha, só a frase.
  fixed: { type: Boolean, default: false },
});

const placement = defineModel({ type: String, default: 'AUTO' });

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.PLACEMENT';
const open = ref(false);
const canChange = computed(() => !props.fixed && props.options.length > 1);

const choose = option => {
  placement.value = option;
  open.value = false;
};
</script>

<template>
  <div
    data-create-placement
    class="flex flex-col gap-2 rounded-xl bg-n-alpha-1 p-4"
  >
    <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
      <span class="text-xs font-semibold text-n-slate-11">
        {{ $t(`${KEY}.TITLE`) }}
      </span>
      <button
        v-if="canChange"
        type="button"
        data-create-placement-change
        :aria-expanded="open"
        class="-my-2 inline-flex min-h-11 items-center gap-1.5 rounded-lg border-0 bg-transparent px-3 text-sm font-520 text-n-brand focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="open = !open"
      >
        {{ $t(`${KEY}.CHANGE`) }}
        <span
          :class="open ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          class="size-4"
          aria-hidden="true"
        />
      </button>
    </div>
    <p
      v-if="fixed || !open"
      data-create-review-where
      class="m-0 text-sm text-n-slate-12"
    >
      {{
        fixed ? $t(`${KEY}.FACEBOOK_POST`) : $t(`${KEY}.OPTIONS.${placement}`)
      }}
    </p>
    <p v-if="!fixed && !open" class="m-0 text-xs text-n-slate-11">
      {{ $t(`${KEY}.HINTS.${placement}`) }}
    </p>
    <div
      v-if="open"
      role="radiogroup"
      :aria-label="$t(`${KEY}.TITLE`)"
      class="flex flex-col gap-2"
    >
      <button
        v-for="option in options"
        :key="option"
        type="button"
        role="radio"
        :aria-checked="placement === option"
        :data-create-placement-option="option"
        class="flex min-h-11 flex-col items-start gap-0.5 rounded-xl border-0 p-3 text-start focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="
          placement === option
            ? 'bg-n-brand/10 ring-2 ring-n-brand'
            : 'bg-n-solid-1 ring-1 ring-n-weak'
        "
        @click="choose(option)"
      >
        <span class="text-sm font-semibold text-n-slate-12">
          {{ $t(`${KEY}.OPTIONS.${option}`) }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ $t(`${KEY}.HINTS.${option}`) }}
        </span>
      </button>
    </div>
  </div>
</template>
