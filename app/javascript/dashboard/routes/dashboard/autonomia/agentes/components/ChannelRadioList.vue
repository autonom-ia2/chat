<script setup>
import { useI18n } from 'vue-i18n';

const props = defineProps({
  channels: { type: Array, default: () => [] },
  modelValue: { type: [String, Number], default: null },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const select = channel => {
  if (props.disabled || channel.busy) return;
  emit('update:modelValue', channel.id);
};
</script>

<template>
  <div
    class="flex flex-col gap-2"
    role="radiogroup"
    :aria-label="t('AGENTS.CREATION.live.channelLabel')"
  >
    <button
      v-for="channel in channels"
      :key="channel.id"
      type="button"
      role="radio"
      :data-channel-id="channel.id"
      :aria-checked="modelValue === channel.id"
      :aria-disabled="disabled || channel.busy"
      :disabled="disabled || channel.busy"
      class="flex items-center min-h-11 gap-3 px-3 py-2 text-left transition-colors border rounded-xl border-n-weak bg-n-solid-1 hover:border-n-brand disabled:cursor-not-allowed disabled:opacity-60"
      :class="
        modelValue === channel.id
          ? 'border-n-brand bg-n-iris-2 ring-1 ring-n-brand'
          : ''
      "
      @click="select(channel)"
    >
      <span
        class="flex items-center justify-center rounded-lg size-9 shrink-0 bg-n-alpha-2 text-n-slate-11"
        aria-hidden="true"
      >
        <i class="i-lucide-radio size-4" />
      </span>
      <span class="flex flex-col flex-1 min-w-0 gap-0.5">
        <strong class="text-sm font-medium truncate text-n-slate-12">
          {{ channel.name }}
        </strong>
        <span v-if="channel.busy" class="text-xs text-n-amber-11">
          {{ channel.reason || t('AGENTS.CREATION.live.channelBusy') }}
        </span>
        <span v-else class="text-xs text-n-slate-11">
          {{ channel.provider || t('AGENTS.CREATION.live.channelReady') }}
        </span>
      </span>
      <span
        class="flex items-center justify-center rounded-full size-5 border border-n-slate-8"
        :class="modelValue === channel.id ? 'border-4 border-n-brand' : ''"
        aria-hidden="true"
      />
    </button>
    <p
      v-if="!channels.length"
      class="p-3 text-sm leading-5 rounded-xl bg-n-alpha-1 text-n-slate-11"
    >
      {{ t('AGENTS.CREATION.live.noChannels') }}
    </p>
  </div>
</template>
