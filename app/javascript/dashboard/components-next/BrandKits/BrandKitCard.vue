<script setup>
// One identity in the list (#1076): the logo on its top band, name, "Padrão", site and fonts, the
// main colors, "Alterar" and the "more" menu (Tornar padrão, Arquivar). Archiving asks inside the
// card; the default cannot be archived. An archived card offers "Restaurar".
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Button from 'dashboard/components-next/button/Button.vue';
import { DOT } from 'dashboard/components-next/CampaignJourney/textMarks';
import { kitFonts, kitLogoUrl, kitSwatches, siteHost } from './brandKitData';
import { textOn } from './brandColors';

const props = defineProps({
  kit: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  busy: { type: Boolean, default: false },
});

const emit = defineEmits(['edit', 'makeDefault', 'archive', 'restore']);

const NS = 'BRAND_KITS.CARD';
const { t } = useI18n();
const menuOpen = ref(false);
const confirming = ref(false);

const isArchived = computed(() => Boolean(props.kit.archived_at));
const band = computed(
  () => props.kit.appearance?.palettes?.light?.band || '#ffffff'
);
const logoUrl = computed(() => kitLogoUrl(props.kit));
const details = computed(() =>
  [
    siteHost(props.kit.source_url) || t(`${NS}.NO_SITE`),
    kitFonts(props.kit.appearance).join(t(`${NS}.AND`)),
  ]
    .filter(Boolean)
    .join(` ${DOT} `)
);

const askArchive = () => {
  menuOpen.value = false;
  confirming.value = true;
};
const makeDefault = () => {
  menuOpen.value = false;
  emit('makeDefault', props.kit);
};
</script>

<template>
  <article
    class="flex flex-col rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
    :data-kit="kit.id"
  >
    <div
      class="flex h-24 items-center justify-center rounded-t-2xl px-6"
      :style="{ backgroundColor: band }"
    >
      <img
        v-if="logoUrl"
        :src="logoUrl"
        :alt="kit.name"
        class="max-h-12 max-w-[12rem] object-contain"
      />
      <span v-else class="text-xl font-bold" :style="{ color: textOn(band) }">
        {{ kit.name }}
      </span>
    </div>
    <div class="flex flex-col gap-3 p-5">
      <div class="flex flex-wrap items-center gap-2">
        <h3 class="m-0 text-base font-semibold text-n-slate-12">
          {{ kit.name }}
        </h3>
        <span
          v-if="kit.is_default"
          class="inline-flex items-center gap-1 rounded-full bg-n-blue-3 px-2 py-0.5 text-xs font-medium text-n-blue-11"
          data-test="default-badge"
        >
          <span class="i-lucide-star size-3" aria-hidden="true" />
          {{ t(`${NS}.DEFAULT`) }}
        </span>
        <span
          v-if="isArchived"
          class="inline-flex rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
        >
          {{ t(`${NS}.ARCHIVED`) }}
        </span>
      </div>
      <p class="m-0 truncate text-sm text-n-slate-11">{{ details }}</p>
      <div class="flex gap-2" aria-hidden="true">
        <span
          v-for="(color, index) in kitSwatches(kit.appearance)"
          :key="index"
          class="size-6 rounded-full border border-n-weak"
          :style="{ backgroundColor: color }"
        />
      </div>
      <div v-if="canManage && !isArchived" class="flex gap-2">
        <Button
          :label="t(`${NS}.EDIT`)"
          icon="i-lucide-pencil"
          variant="outline"
          color="slate"
          class="!min-h-11 !rounded-xl"
          data-test="kit-edit"
          @click="emit('edit', kit)"
        />
        <div v-on-click-outside="() => (menuOpen = false)" class="relative">
          <Button
            icon="i-lucide-ellipsis"
            variant="outline"
            color="slate"
            class="!min-h-11 !min-w-11 !rounded-xl"
            :aria-label="t(`${NS}.MORE`, { name: kit.name })"
            :aria-expanded="menuOpen"
            aria-haspopup="menu"
            data-test="kit-more"
            @click="menuOpen = !menuOpen"
          />
          <div
            v-if="menuOpen"
            role="menu"
            class="absolute start-0 top-full z-20 mt-2 w-64 rounded-xl border border-n-weak bg-n-solid-1 p-1 shadow-lg"
          >
            <button
              v-if="!kit.is_default"
              type="button"
              role="menuitem"
              class="flex min-h-11 w-full items-start gap-3 rounded-lg px-3 py-2 text-start hover:bg-n-alpha-1"
              data-test="kit-make-default"
              @click="makeDefault"
            >
              <span
                class="i-lucide-star mt-0.5 size-4 shrink-0"
                aria-hidden="true"
              />
              <span>
                <span class="block text-sm text-n-slate-12">{{
                  t(`${NS}.MAKE_DEFAULT`)
                }}</span>
                <span class="block text-xs text-n-slate-11">{{
                  t(`${NS}.MAKE_DEFAULT_HINT`)
                }}</span>
              </span>
            </button>
            <button
              type="button"
              role="menuitem"
              class="flex min-h-11 w-full items-start gap-3 rounded-lg px-3 py-2 text-start hover:bg-n-alpha-1 disabled:cursor-not-allowed disabled:opacity-60"
              :disabled="kit.is_default"
              data-test="kit-archive"
              @click="askArchive"
            >
              <span
                class="i-lucide-archive mt-0.5 size-4 shrink-0"
                aria-hidden="true"
              />
              <span>
                <span class="block text-sm text-n-slate-12">{{
                  t(`${NS}.ARCHIVE`)
                }}</span>
                <span class="block text-xs text-n-slate-11">
                  {{
                    kit.is_default
                      ? t(`${NS}.ARCHIVE_DEFAULT_HINT`)
                      : t(`${NS}.ARCHIVE_HINT`)
                  }}
                </span>
              </span>
            </button>
          </div>
        </div>
      </div>
      <div v-if="canManage && isArchived">
        <Button
          :label="t(`${NS}.RESTORE`)"
          icon="i-lucide-archive-restore"
          variant="outline"
          color="slate"
          class="!min-h-11 !rounded-xl"
          :is-loading="busy"
          data-test="kit-restore"
          @click="emit('restore', kit)"
        />
      </div>
    </div>
    <div
      v-if="confirming"
      class="flex flex-col gap-3 rounded-b-2xl border-t border-n-ruby-4 bg-n-ruby-2 p-5"
      role="alertdialog"
      :aria-label="t(`${NS}.ARCHIVE_CONFIRM_TITLE`, { name: kit.name })"
    >
      <p class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.ARCHIVE_CONFIRM_TITLE`, { name: kit.name }) }}
      </p>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.ARCHIVE_CONFIRM_TEXT`) }}
      </p>
      <div class="flex gap-2">
        <Button
          :label="t(`${NS}.ARCHIVE`)"
          icon="i-lucide-archive"
          color="ruby"
          class="!min-h-11 !rounded-xl"
          :is-loading="busy"
          data-test="kit-archive-confirm"
          @click="emit('archive', kit)"
        />
        <Button
          :label="t(`${NS}.BACK`)"
          variant="outline"
          color="slate"
          class="!min-h-11 !rounded-xl"
          @click="confirming = false"
        />
      </div>
    </div>
  </article>
</template>
