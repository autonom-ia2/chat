<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import EmailCampaignAiAPI from 'dashboard/api/emailCampaignAi';
import EmailCampaignAssetsAPI from 'dashboard/api/emailCampaignAssets';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

const props = defineProps({
  campaignId: {
    type: Number,
    required: true,
  },
  placeholders: {
    type: Array,
    default: () => [],
  },
  // Current canvas MJML when a design/template is already loaded. Enables the
  // "adapt this template" mode: the AI keeps the structure and rewrites the copy.
  baseMjml: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['close', 'generationStarted']);

const { t } = useI18n();

const tk = key => {
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return t(`CAMPAIGN.EMAIL_CAMPAIGN.AI.COMPOSER.${key}`);
};

const chipLabel = key => `{{ ${key} }}`;

const ROLE_OPTIONS = ['logo', 'product', 'banner', 'testimonial', 'other'];
const roleChoices = computed(() =>
  ROLE_OPTIONS.map(role => ({
    value: role,
    label: tk(`ROLE_${role.toUpperCase()}`),
  }))
);

const brief = ref('');
const assets = ref([]); // { id, kind, url, signedId, videoUrl, posterUrl, provider, description, role }
const videoLink = ref('');

// When a design is already loaded, default to ADAPTING it (preserve structure,
// rewrite copy to the brief). The user can switch to a from-scratch generation.
const hasBase = computed(() => props.baseMjml.trim().length > 0);
const adaptDesign = ref(true);

const isGenerating = ref(false);
const isUploadingImage = ref(false);
const isUploadingPdf = ref(false);
const isResolvingVideo = ref(false);
const errorMessage = ref('');

const imageInput = ref(null);
const pdfInput = ref(null);
const videoInput = ref(null);

let assetSeq = 0;

const isBusy = computed(
  () => isUploadingImage.value || isUploadingPdf.value || isResolvingVideo.value
);

const canGenerate = computed(
  () => brief.value.trim().length > 0 && !isGenerating.value && !isBusy.value
);

const close = () => emit('close');

const humanizeError = error => {
  const code = error?.response?.data?.error;
  if (code === 'ai_not_configured') {
    return tk('NOT_CONFIGURED');
  }
  if (code === 'email_campaign.base_mjml_too_large') {
    return tk('BASE_TOO_LARGE');
  }
  return tk('ERROR');
};

const addAsset = asset => {
  assetSeq += 1;
  assets.value.push({
    id: assetSeq,
    role: ROLE_OPTIONS[0],
    description: '',
    ...asset,
  });
};

const removeAsset = id => {
  assets.value = assets.value.filter(asset => asset.id !== id);
};

const pickImage = () => imageInput.value?.click();
const pickPdf = () => pdfInput.value?.click();
const pickVideo = () => videoInput.value?.click();

const onImageChange = async event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;

  isUploadingImage.value = true;
  errorMessage.value = '';
  try {
    const { data } = await EmailCampaignAssetsAPI.upload(
      props.campaignId,
      file
    );
    addAsset({
      kind: 'image',
      url: data.url,
      signedId: data.signed_id,
      name: file.name,
    });
  } catch (error) {
    errorMessage.value = humanizeError(error);
  } finally {
    isUploadingImage.value = false;
  }
};

const onPdfChange = async event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;

  isUploadingPdf.value = true;
  errorMessage.value = '';
  try {
    const { data } = await EmailCampaignAssetsAPI.upload(
      props.campaignId,
      file
    );
    addAsset({
      kind: 'pdf',
      url: data.url,
      signedId: data.signed_id,
      name: file.name,
    });
  } catch (error) {
    errorMessage.value = humanizeError(error);
  } finally {
    isUploadingPdf.value = false;
  }
};

const resolveAndAddVideo = async payload => {
  isResolvingVideo.value = true;
  errorMessage.value = '';
  try {
    const { data } = await EmailCampaignAssetsAPI.resolveVideo(
      props.campaignId,
      payload
    );
    addAsset({
      kind: 'video',
      videoUrl: data.video_url,
      posterUrl: data.poster_url,
      provider: data.provider,
      mjmlBlock: data.mjml_block,
    });
    videoLink.value = '';
  } catch (error) {
    errorMessage.value = humanizeError(error);
  } finally {
    isResolvingVideo.value = false;
  }
};

const addVideoLink = () => {
  const url = videoLink.value.trim();
  if (!url || isResolvingVideo.value) return;
  resolveAndAddVideo({ url });
};

const onVideoChange = async event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;

  isResolvingVideo.value = true;
  errorMessage.value = '';
  try {
    const { data } = await EmailCampaignAssetsAPI.upload(
      props.campaignId,
      file
    );
    await resolveAndAddVideo({ signedId: data.signed_id });
  } catch (error) {
    errorMessage.value = humanizeError(error);
    isResolvingVideo.value = false;
  }
};

const assetIcon = kind => {
  if (kind === 'image') return 'i-lucide-image';
  if (kind === 'pdf') return 'i-lucide-file-text';
  return 'i-lucide-play';
};

const buildPayloadAssets = () =>
  assets.value.map(asset => {
    const base = {
      kind: asset.kind,
      description: asset.description?.trim() || '',
      role: asset.role,
    };
    if (asset.kind === 'video') {
      return {
        ...base,
        video_url: asset.videoUrl,
        poster_url: asset.posterUrl,
      };
    }
    return { ...base, url: asset.url, signed_id: asset.signedId };
  });

// Geração ASSÍNCRONA: dispara o job (202) e entrega o controle ao popup de geração. O resultado
// é persistido na campanha pelo backend (durável) e o builder recarrega o MJML quando concluir.
const generate = async () => {
  if (!canGenerate.value) return;

  isGenerating.value = true;
  errorMessage.value = '';
  try {
    await EmailCampaignAiAPI.generate({
      campaignId: props.campaignId,
      brief: brief.value.trim(),
      placeholders: props.placeholders,
      assets: buildPayloadAssets(),
      baseMjml: hasBase.value && adaptDesign.value ? props.baseMjml : undefined,
    });
    emit('generationStarted');
    close();
  } catch (error) {
    errorMessage.value = humanizeError(error);
  } finally {
    isGenerating.value = false;
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
    @click.self="close"
  >
    <div
      class="flex max-h-[88vh] w-[min(42rem,calc(100vw-3rem))] min-w-0 flex-col overflow-hidden rounded-xl border border-n-weak bg-n-solid-2 shadow-xl"
    >
      <div
        class="flex items-start justify-between gap-3 p-6 pb-4 border-b border-n-weak"
      >
        <div class="min-w-0">
          <h3 class="mb-1 text-base font-medium leading-6 text-n-slate-12">
            {{ tk('TITLE') }}
          </h3>
          <p class="max-w-xl mb-0 text-sm leading-5 text-n-slate-11">
            {{ tk('SUBTITLE') }}
          </p>
        </div>
        <Button
          icon="i-lucide-x"
          color="slate"
          variant="ghost"
          size="sm"
          @click="close"
        />
      </div>

      <div class="flex flex-col gap-6 p-6 overflow-y-auto">
        <TextArea
          v-model="brief"
          :label="tk('BRIEF_LABEL')"
          :placeholder="tk('BRIEF_PLACEHOLDER')"
          auto-height
          resize
          min-height="7rem"
          max-height="16rem"
        />

        <!-- Modo adaptar: visivel quando ja existe um design/modelo carregado -->
        <label
          v-if="hasBase"
          class="flex items-start gap-2.5 p-3 rounded-lg cursor-pointer border border-n-weak bg-n-alpha-1"
        >
          <input
            v-model="adaptDesign"
            type="checkbox"
            class="mt-0.5 accent-n-brand size-4"
          />
          <span class="flex flex-col gap-0.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{ tk('ADAPT_LABEL') }}
            </span>
            <span class="text-xs leading-4 text-n-slate-11">
              {{ tk('ADAPT_HINT') }}
            </span>
          </span>
        </label>

        <!-- Placeholders da base disponiveis -->
        <div v-if="placeholders.length" class="flex flex-col gap-2">
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ tk('PLACEHOLDERS_LABEL') }}
          </p>
          <p class="mb-0 text-xs leading-4 text-n-slate-11">
            {{ tk('PLACEHOLDERS_HINT') }}
          </p>
          <div class="flex flex-wrap gap-1.5">
            <span
              v-for="key in placeholders"
              :key="key"
              class="inline-flex items-center px-2 py-1 font-mono text-xs rounded-md text-n-slate-12 bg-n-alpha-2"
            >
              {{ chipLabel(key) }}
            </span>
          </div>
        </div>

        <!-- Secao ASSETS -->
        <div class="flex flex-col gap-3">
          <div>
            <p class="mb-1 text-sm font-medium text-n-slate-12">
              {{ tk('ASSETS_LABEL') }}
            </p>
            <p class="mb-0 text-xs leading-4 text-n-slate-11">
              {{ tk('ASSETS_HINT') }}
            </p>
          </div>

          <input
            ref="imageInput"
            type="file"
            accept="image/*"
            class="hidden"
            @change="onImageChange"
          />
          <input
            ref="pdfInput"
            type="file"
            accept="application/pdf"
            class="hidden"
            @change="onPdfChange"
          />
          <input
            ref="videoInput"
            type="file"
            accept="video/*"
            class="hidden"
            @change="onVideoChange"
          />

          <div class="flex flex-wrap gap-2">
            <Button
              type="button"
              color="slate"
              variant="faded"
              size="sm"
              icon="i-lucide-image"
              :label="tk('ADD_IMAGE')"
              :is-loading="isUploadingImage"
              :disabled="isBusy"
              @click="pickImage"
            />
            <Button
              type="button"
              color="slate"
              variant="faded"
              size="sm"
              icon="i-lucide-file-text"
              :label="tk('ADD_PDF')"
              :is-loading="isUploadingPdf"
              :disabled="isBusy"
              @click="pickPdf"
            />
            <Button
              type="button"
              color="slate"
              variant="faded"
              size="sm"
              icon="i-lucide-upload"
              :label="tk('ADD_VIDEO_FILE')"
              :is-loading="isResolvingVideo"
              :disabled="isBusy"
              @click="pickVideo"
            />
          </div>

          <!-- Video por LINK -->
          <div class="flex items-end gap-2">
            <div class="flex-1 min-w-0">
              <Input
                v-model="videoLink"
                size="sm"
                :label="tk('VIDEO_LINK_LABEL')"
                :placeholder="tk('VIDEO_LINK_PLACEHOLDER')"
                @enter="addVideoLink"
              />
            </div>
            <Button
              type="button"
              color="slate"
              variant="outline"
              size="sm"
              icon="i-lucide-plus"
              :label="tk('VIDEO_LINK_ADD')"
              :disabled="!videoLink.trim() || isBusy"
              @click="addVideoLink"
            />
          </div>

          <!-- Lista editavel de assets -->
          <div v-if="assets.length" class="flex flex-col gap-2">
            <div
              v-for="asset in assets"
              :key="asset.id"
              class="flex gap-3 p-3 rounded-lg border border-n-weak bg-n-alpha-1"
            >
              <div
                class="flex items-center justify-center overflow-hidden rounded-md shrink-0 size-12 bg-n-alpha-2"
              >
                <img
                  v-if="asset.kind === 'image' && asset.url"
                  :src="asset.url"
                  alt=""
                  class="object-cover size-full"
                />
                <img
                  v-else-if="asset.kind === 'video' && asset.posterUrl"
                  :src="asset.posterUrl"
                  alt=""
                  class="object-cover size-full"
                />
                <span
                  v-else
                  :class="assetIcon(asset.kind)"
                  class="size-5 text-n-slate-11"
                />
              </div>

              <div class="flex flex-col flex-1 min-w-0 gap-2">
                <div class="flex items-center gap-2">
                  <span
                    class="inline-flex items-center gap-1 px-1.5 py-0.5 text-[11px] font-medium uppercase rounded text-n-slate-11 bg-n-alpha-2"
                  >
                    <span :class="assetIcon(asset.kind)" class="size-3" />
                    {{ tk('KIND_' + asset.kind.toUpperCase()) }}
                  </span>
                  <span
                    v-if="asset.provider"
                    class="text-[11px] capitalize text-n-slate-11"
                  >
                    {{ asset.provider }}
                  </span>
                  <span
                    v-if="asset.name"
                    class="text-xs truncate text-n-slate-11"
                  >
                    {{ asset.name }}
                  </span>
                  <Button
                    icon="i-lucide-trash-2"
                    color="ruby"
                    variant="ghost"
                    size="xs"
                    class="ltr:ml-auto rtl:mr-auto"
                    @click="removeAsset(asset.id)"
                  />
                </div>

                <div class="flex flex-col gap-2 sm:flex-row">
                  <Input
                    v-model="asset.description"
                    size="sm"
                    class="flex-1 min-w-0"
                    :placeholder="tk('ASSET_DESCRIPTION_PLACEHOLDER')"
                  />
                  <ChoiceSelect
                    v-model="asset.role"
                    :options="roleChoices"
                    :aria-label="tk('ASSET_ROLE_LABEL')"
                    class="shrink-0"
                  />
                </div>
              </div>
            </div>
          </div>
        </div>

        <p v-if="errorMessage" class="mb-0 text-sm text-n-ruby-9">
          {{ errorMessage }}
        </p>
      </div>

      <div
        class="flex items-center justify-between w-full gap-3 p-6 pt-4 border-t border-n-weak bg-n-alpha-2"
      >
        <Button
          variant="faded"
          color="slate"
          type="button"
          :label="tk('CANCEL')"
          class="w-full"
          @click="close"
        />
        <Button
          type="button"
          color="blue"
          icon="i-lucide-sparkles"
          :label="tk('GENERATE')"
          class="w-full"
          :is-loading="isGenerating"
          :disabled="!canGenerate"
          @click="generate"
        />
      </div>
    </div>
  </div>
</template>
