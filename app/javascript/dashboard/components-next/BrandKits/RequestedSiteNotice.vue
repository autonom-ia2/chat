<script setup>
// #1111: the request named a site for the identity of the e-mail. One sentence: the site was used, as asked
// (with "Salvar como identidade", the same save as "Usar outro site", #1076), or it could not be read and the
// default identity went instead. The reading stays on the server (brand_kit_imports/:id) until saved.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import BrandKitsAPI from 'dashboard/api/brandKits';
import { saveSiteAsKit } from './brandRequest';
import { useBrandKits } from './useBrandKits';

const props = defineProps({
  siteRequest: { type: Object, required: true },
});

const { t } = useI18n();
const { kits, canManage, ensureKits, fetchKits } = useBrandKits();
const saving = ref(false);
const saved = ref(null);
const saveFailed = ref(false);

const host = computed(() => props.siteRequest.host || '');
const used = computed(() => props.siteRequest.status === 'used');
const canSave = computed(
  () =>
    used.value &&
    canManage.value &&
    Boolean(props.siteRequest.import_id) &&
    !saved.value
);
const message = computed(() =>
  used.value
    ? t('BRAND_KITS.SITE_REQUEST.USED', { host: host.value })
    : t('BRAND_KITS.SITE_REQUEST.UNREADABLE', { host: host.value })
);
const outcome = computed(() => {
  if (saveFailed.value) return t('BRAND_KITS.SITE_REQUEST.SAVE_FAILED');
  if (!saved.value) return '';
  return saved.value.withoutLogo
    ? t('BRAND_KITS.PICKER.SAVED_WITHOUT_LOGO', { name: saved.value.name })
    : t('BRAND_KITS.PICKER.SAVED', { name: saved.value.name });
});

const save = async () => {
  saving.value = true;
  saveFailed.value = false;
  try {
    await ensureKits();
    const { data } = await BrandKitsAPI.siteReading(
      props.siteRequest.import_id
    );
    const kit = data.proposal
      ? await saveSiteAsKit(
          data.proposal,
          kits.value.map(item => item.name)
        )
      : null;
    saved.value = kit;
    saveFailed.value = !kit;
    if (kit) fetchKits();
  } catch {
    saveFailed.value = true;
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div
    class="flex flex-col gap-2 rounded-xl p-3 text-sm leading-5"
    :class="
      used ? 'bg-n-teal-3 text-n-teal-12' : 'bg-n-amber-3 text-n-amber-12'
    "
    role="status"
    data-test="site-request"
  >
    <p class="m-0 flex items-start gap-2">
      <span
        class="mt-0.5 size-4 shrink-0"
        :class="used ? 'i-lucide-globe' : 'i-lucide-triangle-alert'"
        aria-hidden="true"
      />
      <span>{{ message }}</span>
    </p>
    <Button
      v-if="canSave"
      :label="t('BRAND_KITS.SITE_REQUEST.SAVE')"
      :is-loading="saving"
      variant="outline"
      color="slate"
      size="sm"
      class="!min-h-11 w-fit !rounded-xl !bg-n-solid-1"
      data-test="site-request-save"
      @click="save"
    />
    <p v-if="outcome" class="m-0 text-xs" data-test="site-request-outcome">
      {{ outcome }}
    </p>
  </div>
</template>
