<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmBookingPagesAPI from 'dashboard/api/crmBookingPages';

// #1196 — "Marcar reuniões": a página de agendamento que a IA usa para
// oferecer horários e marcar. Escolher a página liga a agenda do agente; "Não
// marcar" desliga. Some quando a conta não tem a agenda nova (a API de páginas
// responde 404) ou a pessoa não pode ver as páginas.
const props = defineProps({
  agent: { type: Object, default: () => ({}) },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();

const OFF = '';

const pages = ref([]);
const isAvailable = ref(false);
const selected = ref(OFF);

const options = computed(() => [
  { value: OFF, label: t('BOOKING.AI_AGENT.OFF') },
  ...pages.value.map(page => ({
    value: page.id,
    label: page.enabled
      ? page.title || t('BOOKING.CARD.UNTITLED')
      : t('BOOKING.AI_AGENT.PAUSED_PAGE', {
          title: page.title || t('BOOKING.CARD.UNTITLED'),
        }),
  })),
]);

const selectedPage = computed(() =>
  pages.value.find(page => page.id === selected.value)
);

const loadPages = async () => {
  try {
    const { data } = await CrmBookingPagesAPI.get();
    pages.value = data.payload || [];
    isAvailable.value = true;
  } catch {
    isAvailable.value = false;
  }
};

watch(
  () => props.agent,
  agent => {
    selected.value = agent?.config?.booking_page_id ?? OFF;
  },
  { immediate: true }
);

const handleSubmit = () => {
  emit('submit', selected.value === OFF ? null : selected.value);
};

onMounted(loadPages);
</script>

<template>
  <section
    v-if="isAvailable"
    class="flex flex-col gap-4 pt-2 border-t border-n-weak"
  >
    <div class="flex flex-col">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('BOOKING.AI_AGENT.TITLE') }}
      </h3>
      <p class="m-0 text-xs text-n-slate-10">
        {{ t('BOOKING.AI_AGENT.DESCRIPTION') }}
      </p>
    </div>
    <p
      v-if="!pages.length"
      class="m-0 text-sm text-n-slate-11"
      data-test="agent-booking-empty"
    >
      {{ t('BOOKING.AI_AGENT.EMPTY') }}
    </p>
    <template v-else>
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('BOOKING.AI_AGENT.PAGE_LABEL') }}
        </label>
        <ChoiceSelect
          v-model="selected"
          :options="options"
          :aria-label="t('BOOKING.AI_AGENT.PAGE_LABEL')"
          class="w-full"
        />
        <p
          v-if="selectedPage && !selectedPage.enabled"
          class="m-0 text-xs text-n-amber-11"
          data-test="agent-booking-paused"
        >
          {{ t('BOOKING.AI_AGENT.PAUSED_HINT') }}
        </p>
        <p class="m-0 text-xs text-n-slate-10">
          {{ t('BOOKING.AI_AGENT.HINT') }}
        </p>
      </div>
      <NextButton
        solid
        sm
        :label="t('BOOKING.AI_AGENT.SAVE')"
        :is-loading="isSaving"
        :disabled="isSaving"
        class="w-fit"
        @click="handleSubmit"
      />
    </template>
  </section>
</template>
