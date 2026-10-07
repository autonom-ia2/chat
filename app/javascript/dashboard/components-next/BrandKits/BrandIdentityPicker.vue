<script setup>
// "Identidade" of one e-mail in "Criar com IA" (#1076): the default identity comes chosen;
// "Trocar" lists the others, "Usar outro site" reads a site just for this e-mail (saved as a new
// identity only when the person ticks "Salvar como identidade"), and the e-mail picks the light
// (recommended) or dark version of the colors.
// v-model: { kitId, importId, proposal, mode, saveAsKit }
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { vOnClickOutside } from '@vueuse/components';
import Button from 'dashboard/components-next/button/Button.vue';
import BrandSiteReader from './BrandSiteReader.vue';
import BrandKitMenu from './BrandKitMenu.vue';
import { useBrandKits } from './useBrandKits';
import { kitLogoUrl, siteHost } from './brandKitData';
import { textOn } from './brandColors';

const props = defineProps({
  modelValue: { type: Object, required: true },
});

const emit = defineEmits(['update:modelValue', 'reading']);

const NS = 'BRAND_KITS.PICKER';
const { t } = useI18n();
const router = useRouter();
const { kits, defaultKit, ensureKits } = useBrandKits();
onMounted(ensureKits);
const menuOpen = ref(false);
const otherSite = ref(Boolean(props.modelValue.importId));
// The site was saved as an identity (Criar com IA): show that identity, not the site reader.
watch(
  () => [props.modelValue.kitId, props.modelValue.importId],
  ([kitId, importId]) => {
    if (kitId && !importId) otherSite.value = false;
  }
);

const choice = computed(() => props.modelValue);
const kit = computed(
  () =>
    kits.value.find(item => item.id === choice.value.kitId) ||
    (choice.value.importId ? null : defaultKit.value)
);
const band = computed(
  () => kit.value?.appearance?.palettes?.[choice.value.mode]?.band || '#ffffff'
);

const update = patch =>
  emit('update:modelValue', { ...choice.value, ...patch });

const chooseKit = item => {
  menuOpen.value = false;
  otherSite.value = false;
  update({ kitId: item.id, importId: null, proposal: null, saveAsKit: false });
};
const useOtherSite = () => {
  menuOpen.value = false;
  otherSite.value = true;
};
const backToKit = () => {
  otherSite.value = false;
  update({ importId: null, proposal: null, saveAsKit: false });
};
const onRead = ({ importId, proposal }) =>
  update({ importId, proposal, kitId: null });
// In a new tab: the e-mail being written stays open here.
const seeAll = () => {
  menuOpen.value = false;
  window.open(
    router.resolve({ name: 'campaigns_journey_brand_kits' }).href,
    '_blank',
    'noopener'
  );
};
</script>

<template>
  <section class="flex flex-col gap-3" data-test="identity-picker">
    <p class="m-0 text-sm font-medium text-n-slate-12">
      {{ t(`${NS}.LABEL`) }}
    </p>

    <div
      v-if="!otherSite"
      class="flex flex-wrap items-center gap-3 rounded-xl border border-n-blue-6 bg-n-blue-2 p-3"
    >
      <span
        class="flex h-11 w-20 shrink-0 items-center justify-center overflow-hidden rounded-lg"
        :style="{ backgroundColor: band }"
        aria-hidden="true"
      >
        <img
          v-if="kit && kitLogoUrl(kit)"
          :src="kitLogoUrl(kit)"
          alt=""
          class="max-h-8 max-w-[4.5rem] object-contain"
        />
        <span
          v-else-if="kit"
          class="truncate px-1 text-xs font-bold"
          :style="{ color: textOn(band) }"
        >
          {{ kit.name }}
        </span>
      </span>
      <div class="min-w-0 flex-1">
        <p
          class="m-0 flex flex-wrap items-center gap-2 text-sm font-semibold text-n-slate-12"
        >
          {{ kit ? kit.name : t(`${NS}.NONE`) }}
          <span
            v-if="kit?.is_default"
            class="rounded-full bg-n-blue-3 px-2 py-0.5 text-xs font-medium text-n-blue-11"
          >
            {{ t(`${NS}.DEFAULT`) }}
          </span>
        </p>
        <p class="m-0 text-xs text-n-slate-11">
          {{ kit ? t(`${NS}.KIT_HINT`) : t(`${NS}.NONE_HINT`) }}
        </p>
      </div>
      <div v-on-click-outside="() => (menuOpen = false)" class="relative">
        <Button
          :label="t(`${NS}.CHANGE`)"
          icon="i-lucide-chevron-down"
          trailing-icon
          variant="outline"
          color="slate"
          class="!min-h-11 !rounded-xl !bg-n-solid-1"
          :aria-expanded="menuOpen"
          aria-haspopup="menu"
          data-test="identity-change"
          @click="menuOpen = !menuOpen"
        />
        <BrandKitMenu
          v-if="menuOpen"
          :kits="kits"
          :selected-id="kit?.id ?? null"
          class="w-72"
          @choose="chooseKit"
        >
          <div v-if="kits.length" class="my-1 border-t border-n-weak" />
          <button
            type="button"
            role="menuitem"
            class="flex min-h-11 w-full items-center gap-3 rounded-lg px-3 text-start text-sm text-n-slate-12 hover:bg-n-alpha-1"
            data-test="identity-other-site"
            @click="useOtherSite"
          >
            <span class="i-lucide-globe size-4" aria-hidden="true" />
            {{ t(`${NS}.OTHER_SITE`) }}
          </button>
          <button
            type="button"
            role="menuitem"
            class="flex min-h-11 w-full items-center gap-3 rounded-lg px-3 text-start text-sm font-medium text-n-blue-11 hover:bg-n-alpha-1"
            @click="seeAll"
          >
            <span class="i-lucide-palette size-4" aria-hidden="true" />
            {{ t(`${NS}.SEE_ALL`) }}
          </button>
        </BrandKitMenu>
      </div>
    </div>

    <div
      v-else
      class="flex flex-col gap-3 rounded-xl border border-n-weak p-3"
      data-test="identity-site"
    >
      <p
        class="m-0 flex items-center gap-2 text-sm font-semibold text-n-slate-12"
      >
        <span class="i-lucide-globe size-4" aria-hidden="true" />
        {{ t(`${NS}.OTHER_SITE_TITLE`) }}
      </p>
      <p class="m-0 text-xs text-n-slate-11">
        {{ t(`${NS}.OTHER_SITE_HINT`) }}
      </p>
      <BrandSiteReader
        compact
        @read="onRead"
        @reading="value => emit('reading', value)"
      />
      <label
        v-if="choice.proposal"
        class="flex min-h-11 cursor-pointer items-center gap-3 rounded-lg px-1 text-sm text-n-slate-12"
      >
        <input
          :checked="choice.saveAsKit"
          type="checkbox"
          class="size-5 accent-n-brand"
          data-test="identity-save-as-kit"
          @change="event => update({ saveAsKit: event.target.checked })"
        />
        {{
          t(`${NS}.SAVE_AS_KIT`, {
            name: choice.proposal.name || siteHost(choice.proposal.source_url),
          })
        }}
      </label>
      <div>
        <Button
          :label="
            defaultKit
              ? t(`${NS}.USE_KIT`, { name: defaultKit.name })
              : t(`${NS}.NO_SITE`)
          "
          variant="outline"
          color="slate"
          size="sm"
          class="!min-h-11 !rounded-xl"
          @click="backToKit"
        />
      </div>
    </div>

    <div
      v-if="kit || choice.proposal"
      class="flex flex-wrap gap-2"
      role="radiogroup"
      :aria-label="t(`${NS}.MODE_LABEL`)"
    >
      <button
        v-for="option in ['light', 'dark']"
        :key="option"
        type="button"
        role="radio"
        class="min-h-11 rounded-xl px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="
          choice.mode === option
            ? 'bg-n-blue-2 font-semibold text-n-blue-11 ring-2 ring-n-blue-9'
            : 'text-n-slate-11 ring-1 ring-n-weak hover:bg-n-alpha-1'
        "
        :aria-checked="choice.mode === option"
        :data-identity-mode="option"
        @click="update({ mode: option })"
      >
        {{ t(`${NS}.MODES.${option.toUpperCase()}`) }}
      </button>
    </div>
    <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.ARIAL_NOTE`) }}</p>
  </section>
</template>
