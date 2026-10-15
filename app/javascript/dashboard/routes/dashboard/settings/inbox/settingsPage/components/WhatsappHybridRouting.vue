<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import SummaryCard from 'dashboard/components-next/summary-card/SummaryCard.vue';
import ToggleSwitch from 'dashboard/components-next/toggle-switch/ToggleSwitch.vue';
import WhatsappHybridRoutingWho from './WhatsappHybridRoutingWho.vue';
import WhatsappHybridRoutingPace from './WhatsappHybridRoutingPace.vue';
import WhatsappHybridRoutingPreview from './WhatsappHybridRoutingPreview.vue';
import {
  ROUTING_ORIGINS,
  PACE_RECOMMENDED,
  enabledOriginsFor,
  disabledOriginsFor,
} from '../whatsappHybridState';

// chat#1067/#1487 — envio automático em três perguntas, como o "Editar funil": por onde a mensagem sai (interruptor
// no cabeçalho), quem pode usar o WhatsApp API depois de 24 horas e o ritmo. Cada pergunta é um cartão com a frase
// do que vale hoje; "Alterar" abre a gaveta daquela pergunta, com a prévia ao lado (embaixo no celular).
const props = defineProps({
  state: { type: Object, required: true },
});

const emit = defineEmits(['save']);

const { t, locale } = useI18n();
const R = 'INBOX_MGMT.WHATSAPP_HYBRID.ROUTING';
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tr = (key, params, plural) => t(`${R}.${key}`, params, plural);
const DEFAULT_CAMPAIGN_LIMIT = 10;

const routingOn = computed(() => Boolean(props.state.routing_enabled));
const enabled = computed(() =>
  enabledOriginsFor(props.state.disabled_origins || [])
);
const rate = computed(
  () => props.state.rate_limit_per_minute || PACE_RECOMMENDED
);
const campaignLimit = computed(
  () => props.state.campaign_rate_limit_per_minute || DEFAULT_CAMPAIGN_LIMIT
);

const originName = key => tr(`WHO.ORIGINS.${key.toUpperCase()}.SHORT`);
const listOf = keys =>
  new Intl.ListFormat(locale.value.split('_').join('-'), {
    type: 'conjunction',
  }).format(keys.map(originName));

const whoSummary = computed(() => {
  const keys = ROUTING_ORIGINS.map(origin => origin.key).filter(key =>
    enabled.value.includes(key)
  );
  if (!keys.length) return tr('WHO.NONE');
  return tr('WHO.SUMMARY', { list: listOf(keys) }, keys.length);
});

// Gavetas: rascunho próprio; só "Salvar" grava.
const whoPanel = ref(null);
const pacePanel = ref(null);
const paceForm = ref(null);
const draftEnabled = ref([]);
const draftRate = ref(PACE_RECOMMENDED);

const openWho = () => {
  draftEnabled.value = [...enabled.value];
  whoPanel.value?.open();
};
const openPace = () => {
  draftRate.value = rate.value;
  pacePanel.value?.open();
};
const saveWho = () => {
  emit('save', { disabled_origins: disabledOriginsFor(draftEnabled.value) });
  whoPanel.value?.close();
};
const saveRate = () => {
  if (paceForm.value?.invalid) return;
  emit('save', { rate_limit_per_minute: draftRate.value });
  pacePanel.value?.close();
};
const paceInvalid = computed(() => Boolean(paceForm.value?.invalid));

const setRouting = value => emit('save', { routing_enabled: value });
</script>

<template>
  <section data-hybrid-routing class="flex flex-col gap-3">
    <h2 class="m-0 text-lg font-semibold text-n-slate-12">
      {{ tr('TITLE') }}
    </h2>

    <SummaryCard
      name="way"
      icon="i-lucide-route"
      tone="bg-n-teal-3 text-n-teal-11"
      :title="tr('WAY.TITLE')"
    >
      <template #acao>
        <label
          class="flex items-center gap-2 cursor-pointer shrink-0"
          data-routing-switch
        >
          <span class="sr-only">{{ tr('WAY.SWITCH') }}</span>
          <ToggleSwitch
            :model-value="routingOn"
            @update:model-value="setRouting"
          />
        </label>
      </template>
      <p class="mb-2 text-base font-semibold text-n-slate-12">
        {{ tr('WAY.SWITCH') }}
        <span class="block text-sm font-normal text-n-slate-11">
          {{ tr('WAY.SWITCH_HINT') }}
        </span>
      </p>
      <ul class="flex flex-col gap-2 p-0 m-0 text-sm list-none">
        <li class="flex items-start gap-2">
          <span
            class="i-lucide-message-circle size-4 mt-0.5 shrink-0 text-n-slate-11"
            aria-hidden="true"
          />
          {{ tr('WAY.INSIDE') }}
        </li>
        <li data-way-outside class="flex items-start gap-2">
          <span
            class="size-4 mt-0.5 shrink-0"
            :class="
              routingOn
                ? 'i-lucide-smartphone text-n-teal-11'
                : 'i-lucide-file-check text-n-slate-11'
            "
            aria-hidden="true"
          />
          {{ routingOn ? tr('WAY.OUTSIDE_ON') : tr('WAY.OUTSIDE_OFF') }}
        </li>
        <li class="flex items-start gap-2">
          <span
            class="i-lucide-file-check size-4 mt-0.5 shrink-0 text-n-slate-11"
            aria-hidden="true"
          />
          {{ tr('WAY.TEMPLATES') }}
        </li>
      </ul>
    </SummaryCard>

    <SummaryCard
      name="who"
      icon="i-lucide-users"
      :title="tr('WHO.TITLE')"
      :dimmed="!routingOn"
      :edit-label="tr('EDIT')"
      :edit-aria-label="tr('EDIT_PART', { part: tr('WHO.TITLE') })"
      @edit="openWho"
    >
      <p class="mb-0">
        {{ routingOn ? whoSummary : tr('OFF_HINT') }}
      </p>
    </SummaryCard>

    <SummaryCard
      name="pace"
      icon="i-lucide-gauge"
      tone="bg-n-amber-3 text-n-amber-11"
      :title="tr('PACE.TITLE')"
      :dimmed="!routingOn"
      :edit-label="tr('EDIT')"
      :edit-aria-label="tr('EDIT_PART', { part: tr('PACE.TITLE') })"
      @edit="openPace"
    >
      <p class="mb-0">
        {{ routingOn ? tr('PACE.SUMMARY', { n: rate }) : tr('OFF_HINT') }}
      </p>
    </SummaryCard>

    <SidePanel ref="whoPanel" width="3xl" :title="tr('WHO.DRAWER_TITLE')">
      <div
        class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_17rem]"
        data-who-drawer
      >
        <WhatsappHybridRoutingWho v-model="draftEnabled" />
        <WhatsappHybridRoutingPreview
          :routing-on="routingOn"
          :enabled="draftEnabled"
          :rate="rate"
        />
      </div>
      <template #footer>
        <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Button
            color="slate"
            variant="faded"
            class="min-h-11"
            :label="tr('CANCEL')"
            @click="whoPanel?.close()"
          />
          <Button
            data-save-who
            class="min-h-11"
            :label="tr('SAVE')"
            @click="saveWho"
          />
        </div>
      </template>
    </SidePanel>

    <SidePanel ref="pacePanel" width="3xl" :title="tr('PACE.TITLE')">
      <div
        class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_17rem]"
        data-pace-drawer
      >
        <div class="flex flex-col gap-3">
          <p class="mb-0 text-sm text-n-slate-11">
            {{ tr('PACE.DRAWER_TEXT') }}
          </p>
          <WhatsappHybridRoutingPace
            ref="paceForm"
            v-model="draftRate"
            :campaign-limit="campaignLimit"
          />
        </div>
        <WhatsappHybridRoutingPreview
          :routing-on="routingOn"
          :enabled="enabled"
          :rate="draftRate"
        />
      </div>
      <template #footer>
        <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Button
            color="slate"
            variant="faded"
            class="min-h-11"
            :label="tr('CANCEL')"
            @click="pacePanel?.close()"
          />
          <Button
            data-save-pace
            class="min-h-11"
            :disabled="paceInvalid"
            :label="tr('SAVE')"
            @click="saveRate"
          />
        </div>
      </template>
    </SidePanel>
  </section>
</template>
