<script setup>
import { computed, onMounted, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  SEM_PAGINA,
  idDaPagina,
  useAgendaDoAgente,
} from '../../agentes/composables/useAgendaDoAgente';

// #1196 — "Marcar reuniões": a página de agendamento que a IA usa para
// oferecer horários e marcar. Escolher a página liga a agenda do agente; "Não
// marcar" desliga. Quando aparece (agenda nova na conta, permissão de ver as
// páginas, `booking_available`) é regra de useAgendaDoAgente, a mesma da
// página nova do agente (#1253).
const props = defineProps({
  agent: { type: Object, default: () => ({}) },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();

const fieldId = useId();

const {
  paginas: pages,
  disponivel: isAvailable,
  opcoes: options,
  paginaDe,
  carregar,
} = useAgendaDoAgente(() => props.agent);

const selected = ref(SEM_PAGINA);

const selectedPage = computed(() => paginaDe(selected.value));

watch(
  () => props.agent,
  agent => {
    selected.value = idDaPagina(agent?.config?.booking_page_id);
  },
  { immediate: true }
);

const handleSubmit = () => {
  emit('submit', selected.value === SEM_PAGINA ? null : selected.value);
};

onMounted(carregar);
</script>

<template>
  <div class="contents">
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
          <label :for="fieldId" class="text-sm font-medium text-n-slate-12">
            {{ t('BOOKING.AI_AGENT.PAGE_LABEL') }}
          </label>
          <ChoiceSelect
            v-model="selected"
            :trigger-id="fieldId"
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
  </div>
</template>
