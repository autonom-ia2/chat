<script setup>
// Campaign list (#1076): while the account has no identity, one line invites to create one.
import { onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { useBrandKits } from './useBrandKits';

const { t } = useI18n();
const router = useRouter();
const { kits, loaded, isAvailable, canManage, ensureKits } = useBrandKits();

onMounted(() => {
  if (isAvailable.value) ensureKits();
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="isAvailable && canManage && loaded && !kits.length"
    class="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-n-blue-6 bg-n-blue-2 px-5 py-3"
    data-test="brand-nudge"
  >
    <p class="m-0 flex items-center gap-2 text-sm text-n-slate-12">
      <span class="i-lucide-palette size-4 text-n-blue-11" aria-hidden="true" />
      {{ t('BRAND_KITS.NUDGE.TEXT') }}
    </p>
    <Button
      :label="t('BRAND_KITS.NUDGE.ACTION')"
      icon="i-lucide-globe"
      variant="outline"
      color="slate"
      class="!min-h-11 !rounded-xl !bg-n-solid-1"
      data-test="brand-nudge-action"
      @click="router.push({ name: 'campaigns_journey_brand_kit_new' })"
    />
  </div>
</template>
