<script setup>
import { computed } from 'vue';
import { GOALS, GOAL_ICONS } from '../anuncioNovo';

// Anúncios da Meta (#2564): a primeira pergunta do anúncio novo, "Quando a pessoa tocar no anúncio, para onde ela vai?".
// Três cartões grandes, cada um com quando usar: conversar comigo, meu site, meu perfil do Instagram. Só aparece o
// objetivo que tem destino confirmado para a conta (`destinations`). O que não dá agora fica apagado, com o motivo
// em cor cheia; tocar no que dá já escolhe e segue.
const props = defineProps({
  modelValue: { type: String, default: null },
  // Destinos confirmados para a conta, na ordem da tela.
  destinations: { type: Array, required: true },
  // Alguma Página que a pessoa pode usar tem conta profissional do Instagram com @ (a escolhida, se já escolheu).
  profileReady: { type: Boolean, default: false },
});

const emit = defineEmits(['choose']);

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.GOAL';

const offered = computed(() =>
  Object.keys(GOALS).filter(goal =>
    GOALS[goal].some(option => props.destinations.includes(option))
  )
);

const reasonFor = goal =>
  goal === 'PROFILE' && !props.profileReady ? 'NO_INSTAGRAM' : '';

const choose = goal => {
  if (reasonFor(goal)) return;
  emit('choose', goal);
};
</script>

<template>
  <div
    class="grid grid-cols-1 gap-3 md:grid-cols-3"
    role="radiogroup"
    :aria-label="$t(`${KEY}.TITLE`)"
  >
    <component
      :is="reasonFor(goal) ? 'div' : 'button'"
      v-for="goal in offered"
      :key="goal"
      :type="reasonFor(goal) ? undefined : 'button'"
      role="radio"
      :aria-checked="modelValue === goal"
      :aria-disabled="Boolean(reasonFor(goal)) || undefined"
      :data-create-goal="goal"
      class="flex min-h-11 flex-col items-start gap-2 rounded-2xl border-0 p-5 text-start transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      :class="
        modelValue === goal
          ? 'bg-n-brand/10 ring-2 ring-n-brand'
          : 'bg-n-solid-1 ring-1 ring-n-weak hover:ring-n-strong'
      "
      @click="choose(goal)"
    >
      <span
        :class="[
          GOAL_ICONS[goal],
          reasonFor(goal) ? 'text-n-slate-10' : 'text-n-brand',
        ]"
        class="size-6"
        aria-hidden="true"
      />
      <span
        class="text-base font-semibold"
        :class="reasonFor(goal) ? 'text-n-slate-10' : 'text-n-slate-12'"
      >
        {{ $t(`${KEY}.OPTIONS.${goal}`) }}
      </span>
      <span
        v-if="reasonFor(goal)"
        :data-create-goal-unavailable="goal"
        class="text-sm font-medium text-n-amber-11"
      >
        {{ $t(`${KEY}.REASONS.${reasonFor(goal)}`) }}
      </span>
      <span v-else class="text-sm text-n-slate-11">
        {{ $t(`${KEY}.WHEN.${goal}`) }}
      </span>
    </component>
  </div>
</template>
