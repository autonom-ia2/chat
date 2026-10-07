<script setup>
// Reads a website into an identity proposal (#1076): the person pastes the address, the server
// reads the home page in the background (brand_kit_imports) and this waits, showing what is being
// looked for, until the proposal arrives. Used by Nova identidade and by "Usar outro site".
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import BrandKitsAPI from 'dashboard/api/brandKits';
import { kitFonts, siteColors, siteHost } from './brandKitData';

defineProps({
  compact: { type: Boolean, default: false },
});

const emit = defineEmits(['read', 'reading']);

const NS = 'BRAND_KITS.READER';
const POLL_MS = 1500;
const STEP_MS = 1800;
const ITEMS = ['LOGO', 'COLORS', 'FONTS', 'SOCIAL'];
const { t } = useI18n();

const address = ref('');
const phase = ref('idle'); // idle | reading | done
const errorMessage = ref('');
const proposal = ref(null);
const tick = ref(0);
let pollTimer = null;
let stepTimer = null;

const stop = () => {
  window.clearTimeout(pollTimer);
  window.clearInterval(stepTimer);
};
onBeforeUnmount(stop);

const found = computed(() => {
  if (!proposal.value) return {};
  const appearance = proposal.value.appearance || {};
  return {
    LOGO: (proposal.value.logo_candidates || []).length,
    COLORS: siteColors(appearance).length,
    FONTS: kitFonts(appearance).length,
    SOCIAL: (appearance.social_links || []).length,
  };
});

const itemState = (item, index) => {
  if (phase.value === 'done') return 'done';
  if (index < tick.value) return 'done';
  return index === tick.value ? 'working' : 'waiting';
};

const fail = message => {
  stop();
  phase.value = 'idle';
  errorMessage.value = message || t(`${NS}.ERROR`);
  emit('reading', false);
};

const poll = async importId => {
  try {
    const { data } = await BrandKitsAPI.siteReading(importId);
    if (data.status === 'succeeded') {
      stop();
      proposal.value = data.proposal;
      phase.value = 'done';
      emit('reading', false);
      emit('read', { importId, proposal: data.proposal });
      return;
    }
    if (data.status === 'failed') {
      fail(data.error_message);
      return;
    }
    pollTimer = window.setTimeout(() => poll(importId), POLL_MS);
  } catch {
    fail();
  }
};

const read = async () => {
  if (!address.value.trim() || phase.value === 'reading') return;
  errorMessage.value = '';
  proposal.value = null;
  tick.value = 0;
  phase.value = 'reading';
  emit('reading', true);
  stepTimer = window.setInterval(() => {
    tick.value = Math.min(tick.value + 1, ITEMS.length - 1);
  }, STEP_MS);
  try {
    const { data } = await BrandKitsAPI.readSite(address.value.trim());
    poll(data.id);
  } catch (error) {
    const body = error?.response?.data || {};
    if (body.error === 'brand_kit_import.already_running' && body.id) {
      poll(body.id);
      return;
    }
    fail(body.error_message);
  }
};
</script>

<template>
  <div class="flex flex-col gap-4" data-test="site-reader">
    <template v-if="phase === 'idle'">
      <div class="flex flex-col gap-2 sm:flex-row sm:items-end">
        <Input
          v-model="address"
          class="min-w-0 flex-1"
          type="url"
          :label="compact ? '' : t(`${NS}.ADDRESS_LABEL`)"
          :placeholder="t(`${NS}.ADDRESS_PLACEHOLDER`)"
          custom-input-class="!h-11"
          data-test="site-address"
          @enter="read"
        />
        <Button
          :label="t(`${NS}.READ`)"
          icon="i-lucide-sparkles"
          class="!min-h-11 !rounded-xl"
          :disabled="!address.trim()"
          data-test="site-read"
          @click="read"
        />
      </div>
      <p v-if="errorMessage" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ errorMessage }}
      </p>
    </template>
    <template v-else>
      <p class="m-0 text-sm font-semibold text-n-slate-12">
        {{
          phase === 'done'
            ? t(`${NS}.READ_DONE`, { site: siteHost(proposal?.source_url) })
            : t(`${NS}.READING`, { site: siteHost(address) || address })
        }}
      </p>
      <p v-if="phase === 'reading'" class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.WAIT_HINT`) }}
      </p>
      <ul class="m-0 flex list-none flex-col gap-1 p-0" aria-live="polite">
        <li
          v-for="(item, index) in ITEMS"
          :key="item"
          class="flex min-h-11 items-center gap-3"
          :data-item="item"
          :data-state="itemState(item, index)"
        >
          <span
            class="flex size-7 shrink-0 items-center justify-center rounded-full"
            :class="
              itemState(item, index) === 'done'
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-alpha-2 text-n-blue-11'
            "
            aria-hidden="true"
          >
            <span
              v-if="itemState(item, index) === 'done'"
              class="i-lucide-check size-4"
            />
            <span
              v-else-if="itemState(item, index) === 'working'"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
          </span>
          <span
            class="flex-1 text-sm"
            :class="
              itemState(item, index) === 'waiting'
                ? 'text-n-slate-10'
                : 'text-n-slate-12'
            "
          >
            {{ t(`${NS}.ITEMS.${item}`) }}
          </span>
          <span v-if="phase === 'done'" class="text-xs text-n-slate-11">
            {{ t(`${NS}.FOUND`, { count: found[item] }, found[item]) }}
          </span>
        </li>
      </ul>
    </template>
  </div>
</template>
