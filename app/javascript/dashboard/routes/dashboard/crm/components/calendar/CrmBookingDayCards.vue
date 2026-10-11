<script setup>
// Dia em cartões (#1285), no padrão da página pública (`StepDate`): só os dias
// em que a página atende, o dia do horário mais cedo em destaque e "Ver mais
// dias". Escolha única no padrão WAI-ARIA de grupo de rádios: Tab entra no dia
// escolhido, as setas trocam o dia entre os cartões à vista, Home vai ao
// primeiro dia e End ao último da janela (abrindo os que faltam).
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { dayLabel } from '../../../../../../public_booking_v2/helpers/datetime';

const props = defineProps({
  // Dias oferecidos (AAAA-MM-DD, no fuso da página), em ordem.
  days: { type: Array, required: true },
  label: { type: String, required: true },
  // Dia do horário livre mais cedo; vazio enquanto não se sabe.
  earliestDay: { type: String, default: '' },
});

const day = defineModel({ type: String, default: '' });

const { t, locale } = useI18n();

const PAGE_SIZE = 7;
const KEY_STEPS = {
  ArrowRight: 1,
  ArrowDown: 1,
  ArrowLeft: -1,
  ArrowUp: -1,
};

const visibleCount = ref(PAGE_SIZE);
const group = ref(null);

const items = computed(() =>
  props.days.slice(0, visibleCount.value).map(iso => {
    const text = dayLabel(iso, locale.value);
    const isEarliest = iso === props.earliestDay;
    return {
      iso,
      ...text,
      isEarliest,
      isSelected: iso === day.value,
      spoken: isEarliest
        ? t('CRM_KANBAN.BOOKING_AGENDA.EARLIEST_DAY_SPOKEN', { day: text.full })
        : text.full,
    };
  })
);
const hasMore = computed(() => visibleCount.value < props.days.length);
// O Tab para no dia escolhido; sem escolha à vista, no primeiro cartão.
const tabStop = computed(() =>
  Math.max(
    items.value.findIndex(item => item.isSelected),
    0
  )
);

// O dia escolhido e o mais cedo nunca ficam escondidos atrás do "Ver mais dias".
const reveal = iso => {
  const index = props.days.indexOf(iso);
  if (index < visibleCount.value) return;
  visibleCount.value = Math.ceil((index + 1) / PAGE_SIZE) * PAGE_SIZE;
};
watch(
  () => [props.days, day.value, props.earliestDay],
  () => {
    reveal(day.value);
    reveal(props.earliestDay);
  },
  { immediate: true }
);

const focusCard = async index => {
  await nextTick();
  group.value?.querySelectorAll('[role="radio"]')[index]?.focus();
};

const targetIndex = (key, index) => {
  if (key === 'Home') return 0;
  if (key === 'End') return props.days.length - 1;
  if (!(key in KEY_STEPS)) return -1;
  return (index + KEY_STEPS[key] + items.value.length) % items.value.length;
};

// Escolher o dia já o põe à vista (`reveal`, pelo watch), inclusive o último.
const onKeydown = (event, index) => {
  const target = targetIndex(event.key, index);
  if (target < 0) return;
  event.preventDefault();
  day.value = props.days[target];
  focusCard(target);
};

const showMore = () => {
  const firstNew = visibleCount.value;
  visibleCount.value += PAGE_SIZE;
  focusCard(firstNew);
};
</script>

<template>
  <div class="flex flex-col gap-1.5" data-booking-agenda-days>
    <span class="text-sm font-medium text-n-slate-12">{{ label }}</span>
    <p v-if="!days.length" class="mb-0 text-sm text-n-slate-11">
      {{ t('CRM_KANBAN.BOOKING_AGENDA.NO_DAYS') }}
    </p>
    <div
      v-else
      ref="group"
      role="radiogroup"
      :aria-label="label"
      class="grid grid-cols-[repeat(auto-fill,minmax(4.5rem,1fr))] gap-2"
    >
      <button
        v-for="(item, index) in items"
        :key="item.iso"
        type="button"
        role="radio"
        :aria-checked="item.isSelected"
        :aria-label="item.spoken"
        :tabindex="index === tabStop ? 0 : -1"
        :data-day="item.iso"
        :data-earliest="item.isEarliest || null"
        class="flex min-h-16 flex-col items-center justify-center rounded-lg px-1 py-1.5 outline outline-1 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
        :class="[
          item.isSelected
            ? 'bg-n-brand text-white'
            : 'bg-n-alpha-1 text-n-slate-12 hover:bg-n-alpha-2',
          item.isSelected || item.isEarliest
            ? 'outline-n-brand'
            : 'outline-n-weak',
        ]"
        @click="day = item.iso"
        @keydown="onKeydown($event, index)"
      >
        <span
          v-if="item.isEarliest"
          class="text-xs font-semibold"
          :class="item.isSelected ? 'text-white' : 'text-n-blue-11'"
        >
          {{ t('CRM_KANBAN.BOOKING_AGENDA.EARLIEST_DAY') }}
        </span>
        <span
          class="text-xs capitalize"
          :class="item.isSelected ? 'text-white' : 'text-n-slate-11'"
        >
          {{ item.weekday }}
        </span>
        <span class="text-lg font-semibold tabular-nums leading-tight">
          {{ item.day }}
        </span>
        <span
          class="text-xs"
          :class="item.isSelected ? 'text-white' : 'text-n-slate-11'"
        >
          {{ item.month }}
        </span>
      </button>
    </div>
    <NextButton
      v-if="hasMore"
      type="button"
      link
      slate
      class="min-h-11 self-start"
      icon="i-lucide-chevron-down"
      :label="t('CRM_KANBAN.BOOKING_AGENDA.MORE_DAYS')"
      data-booking-agenda-more-days
      @click="showMore"
    />
  </div>
</template>
