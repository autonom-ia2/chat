<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import EmailCampaignAiAPI from 'dashboard/api/emailCampaignAi';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  campaignId: { type: Number, required: true },
});

// ready -> usuário pediu abrir no editor; close -> sair (geração continua em background)
const emit = defineEmits(['ready', 'close']);

const { t } = useI18n();
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tk = key => t(`CAMPAIGN.EMAIL_CAMPAIGN.AI.GENERATING.${key}`);

const POLL_MS = 4000;
const MAX_MS = 16 * 60 * 1000; // teto de segurança ACIMA do backend (~15 min)

// processing | ready | failed
const phase = ref('processing');
// 'quality_gate_failed' (#1076): the e-mail kept failing the quality check after one repair.
const failureCode = ref('');
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
    if (data.ai_status === 'ready') {
      phase.value = 'ready';
      stop();
      return;
    }
    if (data.ai_status === 'failed') {
      phase.value = 'failed';
      failureCode.value = data.ai_error || '';
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

const openInEditor = () => emit('ready');
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
            {{ tk('TITLE') }}
          </h3>
          <p class="max-w-md mb-0 text-sm leading-6 text-n-slate-11">
            {{ tk('BODY') }}
          </p>
        </div>
        <div class="flex items-center gap-2 text-sm text-n-slate-11">
          <Spinner class="size-4" />
          <span>{{ tk('WORKING') }}</span>
        </div>
        <Button
          :label="tk('LEAVE')"
          color="slate"
          variant="outline"
          class="mt-1"
          @click="leave"
        />
        <p class="mb-0 text-xs text-n-slate-10">
          {{ tk('LEAVE_HINT') }}
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
            {{ tk('FAILED_TITLE') }}
          </h3>
          <p class="max-w-md mb-0 text-sm leading-6 text-n-slate-11">
            {{
              failureCode === 'quality_gate_failed'
                ? t('BRAND_KITS.QUALITY.FAILED')
                : tk('FAILED_BODY')
            }}
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
