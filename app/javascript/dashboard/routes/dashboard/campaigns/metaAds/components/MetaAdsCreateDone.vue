<script setup>
import { computed, onMounted, ref } from 'vue';
import MetaAdsAdStatus from './MetaAdsAdStatus.vue';

// Anúncios da Meta (#2198), criar: criado e pausado. O "Ativar anúncio" fica à mão e mostra o valor por extenso
// antes de o dinheiro começar a sair. Ativado ali mesmo, o título e a frase passam a dizer que está no ar, ou que a
// campanha (ou o grupo) pausada no Gerenciador da Meta ainda segura o anúncio (`held_by`).
const props = defineProps({
  // { ad_id, name, status, budget, in_review }: `in_review` (#2354) quando a Meta já analisa o anúncio recém-criado.
  created: { type: Object, required: true },
  budget: { type: Object, required: true },
});

const emit = defineEmits(['back']);

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR';
const heading = ref(null);

const gestao = ref({
  status: 'PAUSED',
  effective_status: 'PAUSED',
  can_change: true,
  in_review: Boolean(props.created.in_review),
});
// A entrega como a Meta diria: ativo com a campanha ou o grupo pausados fica "Fora do ar".
const HELD_STATUS = { campaign: 'CAMPAIGN_PAUSED', adset: 'ADSET_PAUSED' };
const heldBy = ref(null);
const activated = (status, result) => {
  const held = status === 'ACTIVE' && HELD_STATUS[result?.held_by];
  heldBy.value = held ? result.held_by.toUpperCase() : null;
  gestao.value = {
    ...gestao.value,
    status,
    effective_status: held || status,
  };
};

const live = computed(() => gestao.value.status === 'ACTIVE');
const title = computed(() => {
  if (!live.value) return 'TITLE';
  return heldBy.value ? 'TITLE_HELD' : 'TITLE_ACTIVE';
});
const hint = computed(() => {
  if (!live.value) return `${KEY}.DONE.HINT`;
  return heldBy.value
    ? `CRM_KANBAN.META_ADS_HUB.GESTAO.STATUS.HELD.${heldBy.value}`
    : `${KEY}.DONE.HINT_ACTIVE`;
});

onMounted(() => heading.value?.focus());
</script>

<template>
  <div
    data-create-done
    class="relative flex flex-col items-start gap-3 overflow-hidden rounded-2xl bg-n-heroi px-5 py-6 text-white ring-1 ring-inset ring-white/10 dark:bg-n-heroi-escuro sm:px-8 sm:py-8"
  >
    <span
      aria-hidden="true"
      class="pointer-events-none absolute -end-16 -top-24 size-72 rounded-full border-[3rem] border-n-blue-9 opacity-15"
    />
    <span
      class="i-lucide-circle-check size-8 text-n-teal-9"
      aria-hidden="true"
    />
    <h2
      ref="heading"
      tabindex="-1"
      class="relative m-0 text-xl font-semibold text-white focus:outline-none"
    >
      {{ $t(`${KEY}.DONE.${title}`, { name: created.name }) }}
    </h2>
    <p class="relative m-0 max-w-prose text-sm leading-6 text-white/80">
      {{ $t(hint) }}
    </p>
    <MetaAdsAdStatus
      :ad-id="created.ad_id"
      :ad-name="created.name"
      :gestao="gestao"
      :budget="budget"
      can-manage
      @changed="activated"
    />
    <button
      type="button"
      data-create-done-back
      class="relative inline-flex min-h-11 items-center gap-1.5 rounded-xl border-0 bg-transparent p-0 text-sm font-medium text-white underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
      @click="emit('back')"
    >
      {{ $t(`${KEY}.BACK_TO_PANEL`) }}
    </button>
  </div>
</template>
