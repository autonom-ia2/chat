<script setup>
// "Identidade deste e-mail" in the editor (#1076): which identity the AI used (light or dark),
// "Trocar" (lists the identities; the one picked opens "Ajustar com IA" with the request to apply it
// to the whole e-mail already written, or "Criar com IA" on an empty canvas — #1126), where to change
// the identity for good, the Arial note and what the quality check still points out. A site the
// request itself asked for (#1111) gets its own sentence on top.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { vOnClickOutside } from '@vueuse/components';
import Button from 'dashboard/components-next/button/Button.vue';
import { DOT } from 'dashboard/components-next/CampaignJourney/textMarks';
import RequestedSiteNotice from './RequestedSiteNotice.vue';
import BrandKitMenu from './BrandKitMenu.vue';
import { useBrandKits } from './useBrandKits';

const props = defineProps({
  identity: { type: Object, default: () => ({}) },
  warnings: { type: Array, default: () => [] },
  canManage: { type: Boolean, default: false },
});

// change: { kitId, name } — the identity picked under "Trocar".
const emit = defineEmits(['change']);

const NS = 'BRAND_KITS.EMAIL_PANEL';
const KNOWN_CHECKS = [
  'contrast',
  'button_height',
  'image_alt',
  'subject_variants',
  'html_size_near',
];
const { t } = useI18n();
const router = useRouter();

const hasIdentity = computed(() => Boolean(props.identity?.name));
const modeLabel = computed(() =>
  t(
    `BRAND_KITS.PICKER.MODES.${(props.identity?.mode || 'light').toUpperCase()}`
  )
);
const warningTexts = computed(() => [
  ...new Set(
    props.warnings.map(warning =>
      KNOWN_CHECKS.includes(warning.check)
        ? t(`BRAND_KITS.QUALITY.CHECKS.${warning.check.toUpperCase()}`)
        : t('BRAND_KITS.QUALITY.CHECKS.OTHER')
    )
  ),
]);
const manageHref = computed(
  () => router.resolve({ name: 'campaigns_journey_brand_kits' }).href
);

const { kits, ensureKits } = useBrandKits();
const menuOpen = ref(false);
onMounted(() => {
  if (props.canManage) ensureKits();
});
const choose = kit => {
  menuOpen.value = false;
  emit('change', { kitId: kit.id, name: kit.name });
};
</script>

<template>
  <section
    class="flex flex-col gap-3 border-b border-n-weak p-3"
    data-test="email-identity"
  >
    <h3 class="m-0 text-sm font-semibold text-n-slate-12">
      {{ t(`${NS}.TITLE`) }}
    </h3>
    <RequestedSiteNotice
      v-if="identity.site_request"
      :site-request="identity.site_request"
    />
    <div
      class="flex items-center gap-3 rounded-xl border border-n-blue-6 bg-n-blue-2 p-3"
    >
      <div class="min-w-0 flex-1">
        <p class="m-0 truncate text-sm font-semibold text-n-slate-12">
          {{ hasIdentity ? identity.name : t(`${NS}.NONE`) }}
        </p>
        <p v-if="hasIdentity" class="m-0 text-xs text-n-slate-11">
          {{ modeLabel }}
          <template v-if="identity.source === 'site'">
            {{ DOT }} {{ t(`${NS}.FROM_SITE`) }}
          </template>
        </p>
      </div>
      <div
        v-if="canManage"
        v-on-click-outside="() => (menuOpen = false)"
        class="relative"
      >
        <Button
          :label="hasIdentity ? t(`${NS}.CHANGE`) : t(`${NS}.USE`)"
          icon="i-lucide-chevron-down"
          trailing-icon
          variant="outline"
          color="slate"
          size="sm"
          class="!min-h-11 !rounded-xl !bg-n-solid-1"
          :aria-expanded="menuOpen"
          aria-haspopup="menu"
          data-test="email-identity-change"
          @click="menuOpen = !menuOpen"
        />
        <BrandKitMenu
          v-if="menuOpen"
          :kits="kits"
          :selected-id="identity.kit_id ?? null"
          class="w-60"
          @choose="choose"
        >
          <a
            v-if="!kits.length"
            role="menuitem"
            :href="manageHref"
            target="_blank"
            rel="noopener noreferrer"
            class="flex min-h-11 w-full items-center gap-3 rounded-lg px-3 text-sm font-medium text-n-blue-11 hover:bg-n-alpha-1"
          >
            <span class="i-lucide-palette size-4" aria-hidden="true" />
            {{ t('BRAND_KITS.PICKER.SEE_ALL') }}
          </a>
        </BrandKitMenu>
      </div>
    </div>
    <p
      class="m-0 flex items-start gap-2 rounded-xl bg-n-alpha-1 p-3 text-xs leading-5 text-n-slate-11"
    >
      <span class="i-lucide-info mt-0.5 size-4 shrink-0" aria-hidden="true" />
      <span>
        {{ t(`${NS}.FROM_IDENTITY`) }}
        <a
          :href="manageHref"
          target="_blank"
          rel="noopener noreferrer"
          class="font-semibold text-n-blue-11 underline"
        >
          {{ t('BRAND_KITS.TABS.IDENTITY') }}
        </a>
      </span>
    </p>
    <p
      class="m-0 flex items-start gap-2 rounded-xl bg-n-alpha-1 p-3 text-xs leading-5 text-n-slate-11"
    >
      <span class="i-lucide-type mt-0.5 size-4 shrink-0" aria-hidden="true" />
      {{ t('BRAND_KITS.PICKER.ARIAL_NOTE') }}
    </p>
    <div
      v-if="warningTexts.length"
      role="status"
      class="flex flex-col gap-1 rounded-xl bg-n-amber-3 p-3 text-xs leading-5 text-n-amber-12"
      data-test="quality-warnings"
    >
      <p class="m-0 font-semibold">
        {{ t('BRAND_KITS.QUALITY.WARNINGS_TITLE') }}
      </p>
      <p v-for="text in warningTexts" :key="text" class="m-0">{{ text }}</p>
    </div>
  </section>
</template>
