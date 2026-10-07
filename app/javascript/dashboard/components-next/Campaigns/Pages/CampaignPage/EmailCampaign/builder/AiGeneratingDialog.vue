<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import EmailCampaignAiAPI from 'dashboard/api/emailCampaignAi';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  campaignId: { type: Number, required: true },
  // create: a new e-mail; adjust: changes to the e-mail on the screen (#1095), which go straight to the
  // before/after preview when ready.
  mode: { type: String, default: 'create' },
});

// ready -> usuário pediu abrir no editor (no ajuste, emitido sozinho com o estado da geração);
// close -> sair (geração continua em background)
const emit = defineEmits(['ready', 'close']);

const { t } = useI18n();
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tk = key => t(`CAMPAIGN.EMAIL_CAMPAIGN.AI.GENERATING.${key}`);
// A generation resumed after leaving the page has no mode: the adjustment in the status tells it.
const seenAdjustment = ref(false);
const isAdjust = computed(
  () => props.mode === 'adjust' || seenAdjustment.value
);
// Same text key in both modes, ADJUST_ prefixed when adjusting.
const modeKey = key => (isAdjust.value ? `ADJUST_${key}` : key);

// Why an adjustment did not happen, in one plain sentence: the model's own reason when the request cannot
// be done in an e-mail, else what the quality check would not let through, else a known failure.
const KNOWN_FAILURES = ['adjust_unreadable', 'base_mjml_too_large'];
const failure = ref(null);
const failureText = computed(() => {
  const adjustment = failure.value?.ai_adjustment;
  if (adjustment?.reason) return adjustment.reason;
  if (adjustment?.problem)
    return tk(`PROBLEM.${adjustment.problem.toUpperCase()}`);
  const code = failure.value?.ai_error;
  // 'quality_gate_failed' (#1076): the new e-mail kept failing the quality check after one repair.
  if (code === 'quality_gate_failed') return t('BRAND_KITS.QUALITY.FAILED');
  if (isAdjust.value && KNOWN_FAILURES.includes(code)) {
    return tk(`PROBLEM.${code.toUpperCase()}`);
  }
  return tk(modeKey('FAILED_BODY'));
});

const POLL_MS = 4000;
const MAX_MS = 16 * 60 * 1000; // teto de segurança ACIMA do backend (~15 min)

// processing | ready | failed
const phase = ref('processing');
let timer = null;
let startedAt = 0;

const stop = () => {
  if (timer) {
    clearTimeout(timer);
    timer = null;
  }
};

const poll = async () => {
  try {
    const { data } = await EmailCampaignAiAPI.status(props.campaignId);
    if (data.ai_adjustment) seenAdjustment.value = true;
    if (data.ai_status === 'ready') {
      stop();
      if (isAdjust.value) {
        emit('ready', data);
        return;
      }
      phase.value = 'ready';
      return;
    }
    if (data.ai_status === 'failed') {
      failure.value = data;
      phase.value = 'failed';
      stop();
      return;
    }
  } catch (error) {
    // erro transitório de rede no polling: ignora e segue tentando até o teto
  }
  if (Date.now() - startedAt > MAX_MS) {
    phase.value = 'failed';
    stop();
    return;
  }
  timer = setTimeout(poll, POLL_MS);
};

onMounted(() => {
  startedAt = Date.now();
  timer = setTimeout(poll, POLL_MS);
});

onBeforeUnmount(stop);

const openInEditor = () => emit('ready', null);
const leave = () => emit('close');
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
  >
    <div
      class="flex w-[min(34rem,calc(100vw-3rem))] min-w-0 flex-col overflow-hidden rounded-xl border border-n-weak bg-n-solid-2 shadow-xl"
    >
      <!-- Processando -->
      <div
        v-if="phase === 'processing'"
        class="flex flex-col items-center gap-5 p-8 text-center"
      >
        <div class="relative flex items-center justify-center size-16">
          <span
            class="absolute inset-0 rounded-full bg-n-brand/15 animate-ping"
          />
          <span
            class="flex items-center justify-center rounded-full size-16 bg-n-brand/10"
          >
            <span class="i-lucide-sparkles size-7 text-n-brand" />
          </span>
        </div>
        <div>
          <h3 class="mb-2 text-lg font-semibold text-n-slate-12">
            {{ tk(modeKey('TITLE')) }}
          </h3>
          <p class="max-w-md mb-0 text-sm leading-6 text-n-slate-11">
            {{ tk(modeKey('BODY')) }}
          </p>
        </div>
        <div class="flex items-center gap-2 text-sm text-n-slate-11">
          <Spinner class="size-4" />
          <span>{{ tk(modeKey('WORKING')) }}</span>
        </div>
        <Button
          :label="tk('LEAVE')"
          color="slate"
          variant="outline"
          class="mt-1"
          @click="leave"
        />
        <p class="mb-0 text-xs text-n-slate-10">
          {{ tk(modeKey('LEAVE_HINT')) }}
        </p>
      </div>

      <!-- Pronto -->
      <div
        v-else-if="phase === 'ready'"
        class="flex flex-col items-center gap-5 p-8 text-center"
      >
        <span
          class="flex items-center justify-center rounded-full size-16 bg-n-teal-3 text-n-teal-11"
        >
          <span class="i-lucide-party-popper size-7" />
        </span>
        <div>
          <h3 class="mb-2 text-lg font-semibold text-n-slate-12">
            {{ tk('READY_TITLE') }}
          </h3>
          <p class="max-w-md mb-0 text-sm leading-6 text-n-slate-11">
            {{ tk('READY_BODY') }}
          </p>
        </div>
        <Button :label="tk('OPEN_EDITOR')" color="blue" @click="openInEditor" />
      </div>

      <!-- Falhou -->
      <div v-else class="flex flex-col items-center gap-5 p-8 text-center">
        <span
          class="flex items-center justify-center rounded-full size-16 bg-n-ruby-3 text-n-ruby-11"
        >
          <span class="i-lucide-triangle-alert size-7" />
        </span>
        <div>
          <h3 class="mb-2 text-lg font-semibold text-n-slate-12">
            {{ tk(modeKey('FAILED_TITLE')) }}
          </h3>
          <p class="max-w-md mb-0 text-sm leading-6 text-n-slate-11">
            {{ failureText }}
          </p>
        </div>
        <Button
          :label="tk('CLOSE')"
          color="slate"
          variant="outline"
          @click="leave"
        />
      </div>
    </div>
  </div>
</template>
