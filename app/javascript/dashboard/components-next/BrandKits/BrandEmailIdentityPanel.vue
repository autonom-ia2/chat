<script setup>
// "Identidade deste e-mail" in the editor (#1076): which identity the AI used (light or dark),
// "Trocar" (opens "Criar com IA" to redo the e-mail in another identity), where to change the
// identity for good, the Arial note and what the quality check still points out.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { DOT } from 'dashboard/components-next/CampaignJourney/textMarks';

const props = defineProps({
  identity: { type: Object, default: () => ({}) },
  warnings: { type: Array, default: () => [] },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['change']);

const NS = 'BRAND_KITS.EMAIL_PANEL';
const KNOWN_CHECKS = [
  'contrast',
  'button_height',
  'image_alt',
  'subject_variants',
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
</script>

<template>
  <section
    class="flex flex-col gap-3 border-b border-n-weak p-3"
    data-test="email-identity"
  >
    <h3 class="m-0 text-sm font-semibold text-n-slate-12">
      {{ t(`${NS}.TITLE`) }}
    </h3>
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
      <Button
        v-if="canManage"
        :label="hasIdentity ? t(`${NS}.CHANGE`) : t(`${NS}.USE`)"
        variant="outline"
        color="slate"
        size="sm"
        class="!min-h-11 !rounded-xl !bg-n-solid-1"
        data-test="email-identity-change"
        @click="emit('change')"
      />
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
