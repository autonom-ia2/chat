<script setup>
// "Logo, cores e fontes" of an identity (#1076). The kit keeps both e-mail versions — light
// (recommended) and dark (like the site); the switch picks which one is shown and changed. Every
// change goes up as a new form (the page owns it).
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BrandColorRow from './BrandColorRow.vue';
import {
  isLightBand,
  luminance,
  logoTone,
  withColor,
  fontStack,
} from './brandColors';
import { COLOR_ROWS, formLogoUrl, siteColors } from './brandKitData';

const props = defineProps({
  form: { type: Object, required: true },
  mode: { type: String, required: true },
  googleFonts: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:form', 'update:mode']);

const NS = 'BRAND_KITS.LOOK';
const ARIAL = '';
const { t } = useI18n();
const fileInput = ref(null);
const tone = ref(null);

const appearance = computed(() => props.form.appearance);
const palette = computed(() => appearance.value.palettes?.[props.mode] || {});
const siteIsDark = computed(() => {
  const background = appearance.value.site_palette?.background;
  return background ? luminance(background) < 0.35 : false;
});
const foundColors = computed(() => siteColors(appearance.value));
const logoUrl = computed(() => formLogoUrl(props.form));

const logoCards = computed(() => [
  ...(props.form.currentLogoUrl
    ? [
        {
          key: 'current',
          url: props.form.currentLogoUrl,
          label: t(`${NS}.LOGO_CURRENT`),
        },
      ]
    : []),
  ...props.form.logoCandidates.slice(0, 2).map((candidate, index) => ({
    key: `candidate:${index}`,
    url: candidate.url,
    label: t(
      `${NS}.LOGO_FROM_SITE.${candidate.source === 'icon' ? 'ICON' : 'TOP'}`
    ),
    recommended: index === 0,
  })),
  ...(props.form.logoPreviewUrl
    ? [
        {
          key: 'upload',
          url: props.form.logoPreviewUrl,
          label: t(`${NS}.LOGO_UPLOADED`),
        },
      ]
    : []),
]);

watch(
  logoUrl,
  async url => {
    tone.value = await logoTone(url);
  },
  { immediate: true }
);

// White logo on a light band disappears; on a dark band it is fine and worth saying.
const bandNote = computed(() => {
  if (tone.value !== 'light') return null;
  return isLightBand(palette.value.band)
    ? { kind: 'warning', text: t(`${NS}.BAND_TOO_LIGHT`) }
    : { kind: 'info', text: t(`${NS}.WHITE_LOGO_ON_BAND`) };
});

const update = patch => emit('update:form', { ...props.form, ...patch });
const updateAppearance = patch =>
  update({ appearance: { ...appearance.value, ...patch } });

const changeColor = (role, hex) =>
  updateAppearance({
    palettes: {
      ...appearance.value.palettes,
      [props.mode]: withColor(palette.value, props.mode, role, hex),
    },
  });

const resetColors = () =>
  updateAppearance({
    palettes: {
      ...appearance.value.palettes,
      [props.mode]: { ...props.form.suggested[props.mode] },
    },
  });

const fontOptions = computed(() => {
  const families = [
    ...new Set([
      appearance.value.typography?.heading_font,
      appearance.value.typography?.body_font,
      ...props.googleFonts,
    ]),
  ].filter(Boolean);
  return [
    { value: ARIAL, label: t(`${NS}.FONT_ARIAL`) },
    ...families.map(family => ({ value: family, label: family })),
  ];
});

// A new font clears the Google Fonts link: the server fills it again from its catalog.
const changeFont = (key, family) =>
  updateAppearance({
    typography: {
      ...appearance.value.typography,
      [key]: family || null,
      google_font_url: null,
    },
  });

const pickFile = () => fileInput.value?.click();
const onFile = event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;
  update({
    logoFile: file,
    logoPreviewUrl: URL.createObjectURL(file),
    logoChoice: 'upload',
  });
};
</script>

<template>
  <div class="flex flex-col">
    <section class="flex flex-col gap-3 border-b border-n-weak p-5">
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t(`${NS}.LOGO_TITLE`) }}
      </h3>
      <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.LOGO_HINT`) }}</p>
      <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <button
          v-for="card in logoCards"
          :key="card.key"
          type="button"
          class="flex min-h-11 flex-col gap-2 rounded-xl p-2 text-start focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            form.logoChoice === card.key
              ? 'ring-2 ring-n-blue-9'
              : 'ring-1 ring-n-weak hover:bg-n-alpha-1'
          "
          :aria-pressed="form.logoChoice === card.key"
          :data-logo="card.key"
          @click="update({ logoChoice: card.key })"
        >
          <span
            class="flex h-16 items-center justify-center rounded-lg p-2"
            :style="{ backgroundColor: palette.band }"
          >
            <img
              :src="card.url"
              alt=""
              class="max-h-12 max-w-full object-contain"
            />
          </span>
          <span class="text-sm font-medium text-n-slate-12">{{
            card.label
          }}</span>
          <span v-if="card.recommended" class="text-xs text-n-slate-11">
            {{ t(`${NS}.LOGO_RECOMMENDED`) }}
          </span>
        </button>
        <button
          type="button"
          class="flex min-h-11 flex-col gap-2 rounded-xl border border-dashed border-n-weak p-2 text-start hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          data-logo="pick"
          @click="pickFile"
        >
          <span
            class="flex h-16 items-center justify-center rounded-lg bg-n-alpha-1"
          >
            <span
              class="i-lucide-upload size-5 text-n-slate-11"
              aria-hidden="true"
            />
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ t(`${NS}.LOGO_UPLOAD`) }}
          </span>
        </button>
        <input
          ref="fileInput"
          type="file"
          accept="image/png,image/jpeg,image/webp,image/gif"
          class="hidden"
          @change="onFile"
        />
      </div>
      <p
        v-if="bandNote"
        :role="bandNote.kind === 'warning' ? 'alert' : 'status'"
        class="m-0 flex items-start gap-2 rounded-xl px-3 py-2 text-sm"
        :class="
          bandNote.kind === 'warning'
            ? 'bg-n-amber-3 text-n-amber-12'
            : 'bg-n-alpha-1 text-n-slate-11'
        "
        data-test="band-note"
      >
        <span class="i-lucide-info mt-0.5 size-4 shrink-0" aria-hidden="true" />
        {{ bandNote.text }}
      </p>
    </section>

    <section class="flex flex-col gap-3 border-b border-n-weak p-5">
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t(`${NS}.COLORS_TITLE`) }}
      </h3>
      <p class="m-0 text-sm text-n-slate-11">
        {{
          siteIsDark ? t(`${NS}.COLORS_HINT_DARK_SITE`) : t(`${NS}.COLORS_HINT`)
        }}
      </p>
      <div
        class="grid grid-cols-1 gap-2 sm:grid-cols-2"
        role="radiogroup"
        :aria-label="t(`${NS}.MODE_LABEL`)"
      >
        <button
          v-for="option in ['light', 'dark']"
          :key="option"
          type="button"
          role="radio"
          class="flex min-h-11 flex-col items-start rounded-xl px-4 py-3 text-start focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            mode === option
              ? 'ring-2 ring-n-blue-9'
              : 'ring-1 ring-n-weak hover:bg-n-alpha-1'
          "
          :aria-checked="mode === option"
          :data-mode="option"
          @click="emit('update:mode', option)"
        >
          <span
            class="flex items-center gap-2 text-sm font-semibold text-n-slate-12"
          >
            <span
              class="size-3.5 rounded border border-n-weak"
              :style="{
                backgroundColor: appearance.palettes?.[option]?.background,
              }"
              aria-hidden="true"
            />
            {{ t(`${NS}.MODES.${option.toUpperCase()}.LABEL`) }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t(`${NS}.MODES.${option.toUpperCase()}.HINT`) }}
          </span>
        </button>
      </div>
      <p
        v-if="foundColors.length"
        class="m-0 flex flex-wrap items-center gap-1.5 text-xs text-n-slate-11"
      >
        {{ t(`${NS}.FOUND_COLORS`) }}
        <span
          v-for="color in foundColors"
          :key="color"
          class="size-3.5 rounded border border-n-weak"
          :style="{ backgroundColor: color }"
          :title="color"
        />
      </p>
      <ul class="m-0 list-none p-0">
        <BrandColorRow
          v-for="role in COLOR_ROWS"
          :key="`${mode}-${role}`"
          :role="role"
          :color="palette[role]"
          @change="hex => changeColor(role, hex)"
        />
      </ul>
      <div>
        <Button
          :label="t(`${NS}.RESET_COLORS`)"
          variant="link"
          class="!min-h-11"
          data-test="reset-colors"
          @click="resetColors"
        />
      </div>
    </section>

    <section class="flex flex-col gap-4 p-5">
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t(`${NS}.FONTS_TITLE`) }}
      </h3>
      <div
        v-for="key in ['heading_font', 'body_font']"
        :key="key"
        class="flex flex-wrap items-center justify-between gap-3"
      >
        <div class="min-w-0">
          <p class="m-0 text-xs text-n-slate-11">
            {{ t(`${NS}.FONT_ROLES.${key.toUpperCase()}`) }}
          </p>
          <p
            class="m-0 truncate text-xl text-n-slate-12"
            :style="{ fontFamily: fontStack(appearance.typography?.[key]) }"
          >
            {{ appearance.typography?.[key] || t(`${NS}.FONT_ARIAL`) }}
          </p>
        </div>
        <ChoiceSelect
          :model-value="appearance.typography?.[key] || ARIAL"
          :options="fontOptions"
          :aria-label="
            t(`${NS}.FONT_CHANGE`, {
              role: t(`${NS}.FONT_ROLES.${key.toUpperCase()}`),
            })
          "
          :data-font="key"
          @update:model-value="family => changeFont(key, family)"
        />
      </div>
      <p
        class="m-0 flex items-start gap-2 rounded-xl bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-11"
      >
        <span class="i-lucide-info mt-0.5 size-4 shrink-0" aria-hidden="true" />
        <span>
          <strong class="text-n-slate-12">{{ t(`${NS}.ARIAL_TITLE`) }}</strong>
          {{ t(`${NS}.ARIAL_TEXT`) }}
        </span>
      </p>
    </section>
  </div>
</template>
