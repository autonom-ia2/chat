<script setup>
// The list of identities under a "Trocar" button (#1076, #1126): one row per identity (color, name,
// "(padrão)", a check on the one in use). Extra rows (another site, see all) come in the slot. The
// width comes from the parent (class on the component).
import { useI18n } from 'vue-i18n';

defineProps({
  kits: { type: Array, default: () => [] },
  selectedId: { type: Number, default: null },
});

const emit = defineEmits(['choose']);

const { t } = useI18n();
</script>

<template>
  <div
    role="menu"
    class="absolute end-0 top-full z-30 mt-2 rounded-xl border border-n-weak bg-n-solid-1 p-1 shadow-lg"
  >
    <button
      v-for="item in kits"
      :key="item.id"
      type="button"
      role="menuitemradio"
      :aria-checked="selectedId === item.id"
      class="flex min-h-11 w-full items-center gap-3 rounded-lg px-3 text-start text-sm hover:bg-n-alpha-1"
      :class="
        selectedId === item.id
          ? 'font-semibold text-n-blue-11'
          : 'text-n-slate-12'
      "
      :data-kit-option="item.id"
      @click="emit('choose', item)"
    >
      <span
        class="size-5 shrink-0 rounded-full border border-n-weak"
        :style="{
          backgroundColor: item.appearance?.palettes?.light?.primary,
        }"
        aria-hidden="true"
      />
      <span class="flex-1 truncate">{{ item.name }}</span>
      <span
        v-if="item.is_default"
        class="rounded-full bg-n-blue-3 px-2 py-0.5 text-xs font-medium text-n-blue-11"
      >
        {{ t('BRAND_KITS.PICKER.DEFAULT') }}
      </span>
      <span
        v-if="selectedId === item.id"
        class="i-lucide-check size-4 text-n-blue-11"
        aria-hidden="true"
      />
    </button>
    <slot />
  </div>
</template>
