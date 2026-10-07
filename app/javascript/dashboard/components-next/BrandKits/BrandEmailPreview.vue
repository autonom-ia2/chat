<script setup>
// Preview of an e-mail in the identity (#1076): top band with the logo, title in the heading font,
// text, the button, and the canonical locked footer with the identity line and the networks. The
// colors and fonts are the person's data, so they go in :style (Tailwind has no class for them).
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  fontStack,
  previewFontHref,
  textOn,
  FALLBACK_STACK,
} from './brandColors';
import { lockedFooterPreview } from './lockedFooterPreview';
import { NETWORK_LABELS, siteHost } from './brandKitData';

const props = defineProps({
  name: { type: String, default: '' },
  appearance: { type: Object, required: true },
  logoUrl: { type: String, default: '' },
  mode: { type: String, default: 'light' },
  subject: { type: String, default: '' },
});

const NS = 'BRAND_KITS.PREVIEW';
const { t } = useI18n();
const withArial = ref(false);
const footer = lockedFooterPreview();

const palette = computed(() => props.appearance.palettes?.[props.mode] || {});
const typography = computed(() => props.appearance.typography || {});
const headingFont = computed(() =>
  withArial.value ? FALLBACK_STACK : fontStack(typography.value.heading_font)
);
const bodyFont = computed(() =>
  withArial.value ? FALLBACK_STACK : fontStack(typography.value.body_font)
);
const company = computed(
  () => props.appearance.footer?.company_name || props.name
);
const site = computed(() => siteHost(props.appearance.footer?.website));
const networks = computed(() =>
  (props.appearance.social_links || []).map(
    link => NETWORK_LABELS[link.network]
  )
);
const identityLine = computed(() =>
  [company.value, props.appearance.footer?.address].filter(Boolean)
);

// Loads the Google font of the preview once per change; the e-mail itself uses mj-font.
let fontLink = null;
watch(
  () => [typography.value.heading_font, typography.value.body_font],
  families => {
    fontLink?.remove();
    const href = previewFontHref(families);
    if (!href) return;
    fontLink = document.createElement('link');
    fontLink.rel = 'stylesheet';
    fontLink.href = href;
    document.head.appendChild(fontLink);
  },
  { immediate: true }
);
onBeforeUnmount(() => fontLink?.remove());
</script>

<template>
  <section
    class="flex flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1"
    :aria-label="t(`${NS}.TITLE`)"
    data-test="brand-preview"
  >
    <header
      class="flex items-center justify-between gap-3 border-b border-n-weak px-4 py-3"
    >
      <h3 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.TITLE`) }}
      </h3>
      <Button
        :label="withArial ? t(`${NS}.WITH_FONT`) : t(`${NS}.WITH_ARIAL`)"
        icon="i-lucide-type"
        variant="outline"
        color="slate"
        size="sm"
        class="!min-h-11 !rounded-xl"
        :aria-pressed="withArial"
        data-test="preview-arial"
        @click="withArial = !withArial"
      />
    </header>
    <p class="m-0 border-b border-n-weak px-4 py-2 text-xs text-n-slate-11">
      {{ t(`${NS}.FROM`, { name: company }) }}
      <br />
      {{
        t(`${NS}.SUBJECT`, { subject: subject || t(`${NS}.SAMPLE_SUBJECT`) })
      }}
    </p>
    <div class="bg-n-slate-3 p-3 sm:p-4">
      <article
        class="mx-auto w-full max-w-[37.5rem] overflow-hidden rounded-xl"
        :style="{ backgroundColor: palette.background, fontFamily: bodyFont }"
      >
        <div
          class="flex min-h-[4.5rem] items-center justify-center px-6 py-5"
          :style="{ backgroundColor: palette.band }"
          data-test="preview-band"
        >
          <img
            v-if="logoUrl"
            :src="logoUrl"
            :alt="name"
            class="max-h-10 max-w-[11rem] object-contain"
          />
          <span
            v-else
            class="text-xl font-bold"
            :style="{
              color: textOn(palette.band || '#ffffff'),
              fontFamily: headingFont,
            }"
          >
            {{ name }}
          </span>
        </div>
        <div class="px-6 py-6" :style="{ backgroundColor: palette.surface }">
          <span
            class="mb-4 block h-1 w-11 rounded"
            :style="{ backgroundColor: palette.accent }"
          />
          <h4
            class="m-0 text-2xl font-extrabold leading-tight"
            :style="{ color: palette.ink, fontFamily: headingFont }"
          >
            {{ t(`${NS}.SAMPLE_TITLE`) }}
          </h4>
          <p
            class="mb-0 mt-3 text-base leading-relaxed"
            :style="{ color: palette.ink }"
          >
            {{ t(`${NS}.SAMPLE_TEXT`) }}
          </p>
          <ul class="m-0 mt-4 flex list-none flex-col gap-2 p-0">
            <li
              v-for="item in ['ITEM_1', 'ITEM_2', 'ITEM_3']"
              :key="item"
              class="flex items-center gap-3 text-[15px]"
              :style="{ color: palette.ink }"
            >
              <span
                class="size-2 shrink-0 rounded-sm"
                :style="{ backgroundColor: palette.accent }"
              />
              {{ t(`${NS}.${item}`) }}
            </li>
          </ul>
          <span
            class="mt-6 inline-flex min-h-11 items-center rounded-lg px-6 text-base font-bold"
            :style="{
              backgroundColor: palette.primary,
              color: textOn(palette.primary || '#000000'),
            }"
          >
            {{ t(`${NS}.SAMPLE_BUTTON`) }}
          </span>
          <p class="mb-0 mt-4 text-sm" :style="{ color: palette.muted }">
            {{ t(`${NS}.SAMPLE_NOTE`) }}
          </p>
        </div>
        <footer
          class="px-6 py-5 text-center text-xs leading-relaxed"
          :style="{ backgroundColor: footer.background, color: footer.color }"
          data-test="preview-footer"
        >
          <p class="m-0">
            <strong>{{ identityLine.join(' · ') }}</strong>
            <template v-if="site">
              · <span class="underline">{{ site }}</span>
            </template>
          </p>
          <p v-if="networks.length" class="m-0">
            <span class="underline">{{ networks.join(' · ') }}</span>
          </p>
          <p class="m-0">{{ footer.reason }}</p>
          <p class="m-0 underline">{{ footer.unsubscribe }}</p>
        </footer>
      </article>
    </div>
  </section>
</template>
