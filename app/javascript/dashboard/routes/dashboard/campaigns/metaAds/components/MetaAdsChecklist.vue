<script setup>
import { computed } from 'vue';

// Anúncios da Meta (#1047): "o que falta", no padrão do protótipo aprovado — lista vertical ao
// lado do conteúdo, cada passo com o selo Feito / Agora / Desligado. Passo feito tem "Alterar";
// "Avisar vendas" pulado aparece Desligado, com "Ligar" — nunca com o visto.
const props = defineProps({
  // 1 a 4 = passo da vez; 5 = tudo feito.
  current: { type: Number, required: true },
  // Passo aberto agora (pode ser um passo feito, ao alterar).
  open: { type: Number, default: null },
  salesOff: { type: Boolean, default: false },
  // Conta de anúncios gravada sem código do site e sem "Não tenho site" (#2343): o passo não ganha o visto.
  accountPending: { type: Boolean, default: false },
  // Anúncio levando ao site sem página ligada (#2338): o passo do Destino pede a página.
  destinationsPending: { type: Boolean, default: false },
});

defineEmits(['change']);

const STEPS = ['CONNECT', 'ACCOUNT', 'DESTINATIONS', 'SALES'];
const SALES_STEP = 4;
const ACCOUNT_STEP = 2;
const DESTINATIONS_STEP = 3;
// O que falta num passo feito pela metade: a dica e o botão que leva até ele.
const PENDING = {
  [ACCOUNT_STEP]: { hint: 'ACCOUNT_PENDING_HINT', action: 'PICK' },
  [DESTINATIONS_STEP]: { hint: 'DESTINATIONS_PENDING_HINT', action: 'LINK' },
};

const steps = computed(() =>
  STEPS.map((key, index) => {
    const number = index + 1;
    const off = number === SALES_STEP && props.salesOff;
    const flagged = {
      [ACCOUNT_STEP]: props.accountPending,
      [DESTINATIONS_STEP]: props.destinationsPending,
    }[number];
    const pending = number < props.current && Boolean(flagged);
    return {
      key,
      number,
      pending: pending ? PENDING[number] : null,
      done: number < props.current && !off && !pending,
      off: off && number !== props.current,
      now: number === props.current,
      open: number === props.open,
    };
  })
);
</script>

<template>
  <nav
    data-meta-ads-checklist
    :aria-label="$t('CRM_KANBAN.META_ADS_HUB.STEPS.LABEL')"
    class="p-2 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
  >
    <ol class="flex flex-col gap-1 p-0 m-0 list-none">
      <li
        v-for="step in steps"
        :key="step.key"
        :data-step="step.key"
        :aria-current="step.now ? 'step' : undefined"
        class="flex items-center gap-3 px-3 py-3 rounded-xl"
        :class="step.open ? 'bg-n-blue-2' : ''"
      >
        <span
          class="flex items-center justify-center flex-none text-xs font-semibold rounded-full size-7"
          :class="{
            'bg-n-teal-9 text-white': step.done,
            'bg-n-blue-9 text-white': step.now,
            'bg-n-amber-9 text-white': step.pending,
            'bg-n-alpha-2 text-n-slate-11':
              !step.done && !step.now && !step.pending,
          }"
          aria-hidden="true"
        >
          <span v-if="step.done" class="i-lucide-check size-3.5" />
          <span
            v-else-if="step.pending"
            class="i-lucide-alert-triangle size-3.5"
          />
          <template v-else>{{ step.number }}</template>
        </span>
        <span class="flex flex-col flex-1 min-w-0">
          <span
            class="text-sm text-n-slate-12"
            :class="step.now || step.open ? 'font-semibold' : 'font-medium'"
          >
            {{ $t(`CRM_KANBAN.META_ADS_HUB.STEPS.${step.key}`) }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              step.pending
                ? $t(`CRM_KANBAN.META_ADS_HUB.STEPS.${step.pending.hint}`)
                : $t(`CRM_KANBAN.META_ADS_HUB.STEPS.${step.key}_HINT`)
            }}
          </span>
        </span>
        <span
          v-if="step.now"
          class="px-2 py-0.5 text-xs font-semibold rounded-full bg-n-amber-3 text-n-amber-11"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.STEPS.NOW') }}
        </span>
        <button
          v-else-if="step.pending && !step.open"
          type="button"
          data-step-pending
          class="px-3 text-xs font-semibold border-0 rounded-lg min-h-11 bg-n-amber-3 text-n-amber-11 hover:bg-n-amber-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="$emit('change', step.number)"
        >
          {{ $t(`CRM_KANBAN.META_ADS_HUB.STEPS.${step.pending.action}`) }}
        </button>
        <button
          v-else-if="step.off"
          type="button"
          data-step-turn-on
          class="px-3 text-xs font-semibold border-0 rounded-lg min-h-11 bg-n-amber-3 text-n-amber-11 hover:bg-n-amber-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="$emit('change', step.number)"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.STEPS.TURN_ON') }}
        </button>
        <button
          v-else-if="step.done && !step.open"
          type="button"
          class="px-3 text-xs font-semibold bg-transparent border-0 rounded-lg min-h-11 text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="$emit('change', step.number)"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.STEPS.CHANGE') }}
        </button>
        <span
          v-else-if="step.done"
          class="px-2 py-0.5 text-xs font-semibold rounded-full bg-n-teal-3 text-n-teal-11"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.STEPS.DONE') }}
        </span>
      </li>
    </ol>
  </nav>
</template>
