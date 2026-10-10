<script setup>
// Nova identidade and Alterar identidade (#1076). New: Site (read the home page) → Confira
// (part 1 logo, colors and fonts; part 2 networks and footer) → Salvar. Edit: the same two parts as
// tabs. The preview on the side follows every change.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BrandKitsAPI from 'dashboard/api/brandKits';
import BrandSiteReader from './BrandSiteReader.vue';
import BrandLookForm from './BrandLookForm.vue';
import BrandFooterForm from './BrandFooterForm.vue';
import BrandEmailPreview from './BrandEmailPreview.vue';
import { useBrandKits } from './useBrandKits';
import { formFromKit, formLogoUrl, kitPayload } from './brandKitData';

const props = defineProps({
  kitId: { type: [String, Number], default: null },
});

const emit = defineEmits(['saved', 'cancel']);

const NS = 'BRAND_KITS.EDITOR';
const { t } = useI18n();
const { kits, googleFonts, ensureKits, fetchKits } = useBrandKits();

const isNew = computed(() => !props.kitId);
const step = ref(isNew.value ? 'site' : 'look');
const mode = ref('light');
const form = ref(null);
const proposalReady = ref(false);
const isSaving = ref(false);
const errorMessage = ref('');
const isFirst = computed(() => isNew.value && !kits.value.length);

const STEPS = ['site', 'confirm', 'save'];
const stepperIndex = computed(() => (step.value === 'site' ? 0 : 1));

watch(
  () => props.kitId,
  async id => {
    if (!id) return;
    await ensureKits();
    const kit = kits.value.find(item => String(item.id) === String(id));
    form.value = kit ? formFromKit(kit) : null;
  },
  { immediate: true }
);

const onRead = ({ proposal }) => {
  form.value = formFromKit({
    name: proposal.name || '',
    source_url: proposal.source_url,
    appearance: proposal.appearance,
    logo_candidates: proposal.logo_candidates,
  });
  form.value.appearance.footer = {
    ...form.value.appearance.footer,
    company_name:
      form.value.appearance.footer?.company_name || proposal.name || '',
  };
  proposalReady.value = true;
};

const errorText = error => {
  const body = error?.response?.data || {};
  if (body.attributes?.includes('name')) return t(`${NS}.ERRORS.NAME`);
  if (body.attributes?.includes('appearance'))
    return t(`${NS}.ERRORS.APPEARANCE`);
  return t(`${NS}.ERRORS.GENERIC`);
};

const save = async () => {
  if (!form.value.name.trim()) {
    errorMessage.value = t(`${NS}.ERRORS.NAME`);
    step.value = 'footer';
    return;
  }
  isSaving.value = true;
  errorMessage.value = '';
  try {
    const { data } = await BrandKitsAPI.save(
      form.value.id,
      kitPayload(form.value)
    );
    const kit = data.payload || data;
    if (form.value.logoChoice === 'upload' && form.value.logoFile) {
      await BrandKitsAPI.uploadLogo(kit.id, form.value.logoFile);
    }
    await fetchKits();
    emit('saved', { kit, created: isNew.value });
  } catch (error) {
    errorMessage.value = errorText(error);
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <header
      class="flex flex-wrap items-center gap-4 rounded-3xl bg-[#0D2344] px-5 py-5 text-white sm:px-6"
    >
      <Button
        icon="i-lucide-arrow-left"
        variant="ghost"
        color="slate"
        class="!min-h-11 !min-w-11 !rounded-xl !bg-white/10 !text-white"
        :aria-label="t(`${NS}.BACK_TO_LIST`)"
        data-test="editor-back"
        @click="emit('cancel')"
      />
      <h2 class="m-0 min-w-0 flex-1 text-xl font-semibold text-white">
        {{
          isNew
            ? t(`${NS}.NEW_TITLE`)
            : t(`${NS}.EDIT_TITLE`, { name: form?.name || '' })
        }}
      </h2>
      <ol
        v-if="isNew"
        class="m-0 hidden list-none items-center gap-3 p-0 md:flex"
      >
        <li
          v-for="(item, index) in STEPS"
          :key="item"
          class="flex items-center gap-2 text-sm"
          :class="index <= stepperIndex ? 'text-white' : 'text-white/60'"
          :aria-current="index === stepperIndex ? 'step' : undefined"
        >
          <span
            class="flex size-7 items-center justify-center rounded-full text-xs font-semibold"
            :class="
              index < stepperIndex
                ? 'bg-n-teal-9 text-white'
                : index === stepperIndex
                  ? 'bg-n-blue-9 text-white'
                  : 'bg-white/10'
            "
          >
            <span
              v-if="index < stepperIndex"
              class="i-lucide-check size-4"
              aria-hidden="true"
            />
            <template v-else>{{ index + 1 }}</template>
          </span>
          {{ t(`${NS}.STEPS.${item.toUpperCase()}`) }}
        </li>
      </ol>
    </header>

    <section
      v-if="step === 'site'"
      class="mx-auto flex w-full max-w-xl flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
    >
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t(`${NS}.SITE_TITLE`) }}
      </h3>
      <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.SITE_HINT`) }}</p>
      <BrandSiteReader @read="onRead" />
      <div v-if="proposalReady">
        <Button
          :label="t(`${NS}.CHECK`)"
          icon="i-lucide-arrow-right"
          trailing-icon
          class="!min-h-11 !rounded-xl"
          data-test="editor-check"
          @click="step = 'look'"
        />
      </div>
    </section>

    <div v-else-if="!form" class="flex justify-center p-12"><Spinner /></div>

    <template v-else>
      <div v-if="isNew" class="flex items-center gap-2 text-sm">
        <span
          class="rounded-full bg-n-teal-3 px-2 py-0.5 text-xs font-semibold text-n-teal-11"
        >
          {{ t(`${NS}.PART`, { part: step === 'look' ? 1 : 2 }) }}
        </span>
        <span class="text-n-slate-11">
          {{ step === 'look' ? t(`${NS}.TABS.LOOK`) : t(`${NS}.TABS.FOOTER`) }}
        </span>
      </div>
      <nav
        v-else
        class="flex flex-wrap gap-2"
        :aria-label="t(`${NS}.TABS.LABEL`)"
      >
        <button
          v-for="tab in ['look', 'footer']"
          :key="tab"
          type="button"
          class="min-h-11 rounded-full px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            step === tab
              ? 'bg-[#0D2344] text-white'
              : 'text-n-slate-11 ring-1 ring-n-weak hover:bg-n-alpha-1'
          "
          :aria-pressed="step === tab"
          :data-tab="tab"
          @click="step = tab"
        >
          {{ t(`${NS}.TABS.${tab.toUpperCase()}`) }}
        </button>
      </nav>

      <div
        class="grid items-start gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(0,32rem)]"
      >
        <div
          class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1"
        >
          <BrandLookForm
            v-if="step === 'look'"
            v-model:form="form"
            v-model:mode="mode"
            :google-fonts="googleFonts"
          />
          <BrandFooterForm v-else v-model:form="form" :is-first="isFirst" />
          <p
            v-if="errorMessage"
            role="alert"
            class="m-0 px-5 pb-3 text-sm text-n-ruby-11"
          >
            {{ errorMessage }}
          </p>
          <footer
            class="flex items-center justify-between gap-3 border-t border-n-weak p-4"
          >
            <Button
              :label="
                step === 'footer' && isNew ? t(`${NS}.BACK`) : t(`${NS}.CANCEL`)
              "
              :icon="step === 'footer' && isNew ? 'i-lucide-arrow-left' : ''"
              variant="ghost"
              color="slate"
              class="!min-h-11 !rounded-xl"
              @click="
                step === 'footer' && isNew ? (step = 'look') : emit('cancel')
              "
            />
            <Button
              v-if="isNew && step === 'look'"
              :label="t(`${NS}.CONTINUE`)"
              icon="i-lucide-arrow-right"
              trailing-icon
              class="!min-h-11 !rounded-xl"
              data-test="editor-continue"
              @click="step = 'footer'"
            />
            <Button
              v-else
              :label="t(`${NS}.SAVE`)"
              icon="i-lucide-save"
              class="!min-h-11 !rounded-xl"
              :is-loading="isSaving"
              data-test="editor-save"
              @click="save"
            />
          </footer>
        </div>
        <BrandEmailPreview
          class="xl:sticky xl:top-4"
          :name="form.name"
          :appearance="form.appearance"
          :logo-url="formLogoUrl(form)"
          :mode="mode"
        />
      </div>
    </template>
  </div>
</template>
