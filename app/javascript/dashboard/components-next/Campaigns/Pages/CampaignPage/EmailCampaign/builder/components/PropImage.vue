<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';

import EmailCampaignAssetsAPI from 'dashboard/api/emailCampaignAssets';

import { useEmailEditor } from '../composables/useEmailEditor';
// Same reduction/conversion as an image dropped on the canvas (#2908).
import { ImageFileError, UNREADABLE, prepareImageFile } from '../imageFile';

const props = defineProps({
  // bumped on selection/style change -> forces attribute re-read
  revision: {
    type: Number,
    default: 0,
  },
});

const { t } = useI18n();
const route = useRoute();

const { getSelectedAttribute, setSelectedAttribute, setSelectedAttributes } =
  useEmailEditor();

const fileInput = ref(null);
const isUploading = ref(false);
const isFetchingPoster = ref(false);
const error = ref('');

const campaignId = computed(() => route.params.campaignId);

// Reject dangerous schemes on the image link, mirroring PropLink. Strip ASCII
// control chars + whitespace first so "java\nscript:" obfuscations can't slip by.
// eslint-disable-next-line no-control-regex
const CONTROL_WS = /[\u0000-\u0020\u007f]+/g;
const isUnsafeHref = value =>
  /^(javascript|data|vbscript):/.test(
    String(value).replace(CONTROL_WS, '').toLowerCase()
  );

// Local reactive models so edits/uploads reflect instantly. Computed attribute
// reads only react to `props.revision`, which doesn't bump on a write-through;
// these refs re-initialize from the selected component on selection/revision
// change and are updated immediately when the user edits or uploads.
const srcModel = ref('');
const altModel = ref('');
const hrefModel = ref('');

// A YouTube/Vimeo link in the href means this image is a video poster. Offer to
// fetch the real (Gmail-safe, hosted) thumbnail via resolve_video instead of
// leaving the placeholder poster, which is the exact gap that left video emails
// broken when a link was pasted manually.
const VIDEO_HOST_RE = /(youtube\.com|youtu\.be|vimeo\.com)/i;
const isVideoLink = computed(() => VIDEO_HOST_RE.test(hrefModel.value));

watch(
  () => props.revision,
  () => {
    srcModel.value = getSelectedAttribute('src') ?? '';
    altModel.value = getSelectedAttribute('alt') ?? '';
    hrefModel.value = getSelectedAttribute('href') ?? '';
  },
  { immediate: true }
);

const onSrcChange = event => {
  srcModel.value = event.target.value;
  setSelectedAttribute('src', srcModel.value);
};
const onAltChange = event => {
  altModel.value = event.target.value;
  setSelectedAttribute('alt', altModel.value);
};
const onHrefChange = event => {
  const value = event.target.value;
  if (isUnsafeHref(value)) {
    // revert to the persisted value, do not write the unsafe scheme
    hrefModel.value = getSelectedAttribute('href') ?? '';
    return;
  }
  hrefModel.value = value;
  setSelectedAttribute('href', hrefModel.value);
};

// Resolve the pasted YouTube/Vimeo link into a real hosted thumbnail and use it
// as the poster (src). This is the manual counterpart of the AI video flow and
// the fix for posters that stayed broken data: placeholders after a link paste.
const fetchVideoPoster = async () => {
  if (!campaignId.value || !isVideoLink.value) return;
  isFetchingPoster.value = true;
  error.value = '';
  try {
    const { data } = await EmailCampaignAssetsAPI.resolveVideo(
      campaignId.value,
      { url: hrefModel.value }
    );
    // Write src + href in a SINGLE addAttributes so the poster isn't dropped by
    // the second call's re-render (two sequential writes race).
    const attrs = {};
    if (data.poster_url) {
      srcModel.value = data.poster_url;
      attrs.src = data.poster_url;
    }
    if (data.video_url) {
      hrefModel.value = data.video_url;
      attrs.href = data.video_url;
    }
    if (Object.keys(attrs).length) setSelectedAttributes(attrs);
  } catch {
    error.value = t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.IMAGE.POSTER_ERROR');
  } finally {
    isFetchingPoster.value = false;
  }
};

const openPicker = () => {
  error.value = '';
  fileInput.value?.click();
};

// Map a backend asset-validation code to a specific, actionable message so the
// user knows whether to shrink the file or pick another format. Falls back to
// the generic upload error for network/unknown failures.
const uploadErrorMessage = code => {
  if (code === 'email_campaign.asset_too_large') {
    return t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.IMAGE.UPLOAD_TOO_LARGE');
  }
  if (code === 'email_campaign.asset_unsupported_type') {
    return t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.IMAGE.UPLOAD_UNSUPPORTED');
  }
  if (code === UNREADABLE) {
    return t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.IMAGE_DROP.UNREADABLE');
  }
  return t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.IMAGE.UPLOAD_ERROR');
};

const onFile = async event => {
  const file = event.target.files?.[0];
  if (!file) return;
  if (!campaignId.value) {
    error.value = t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.IMAGE.UPLOAD_ERROR');
    if (fileInput.value) fileInput.value.value = '';
    return;
  }
  isUploading.value = true;
  error.value = '';
  try {
    const { data } = await EmailCampaignAssetsAPI.upload(
      campaignId.value,
      await prepareImageFile(file)
    );
    srcModel.value = data.url;
    setSelectedAttribute('src', data.url);
  } catch (e) {
    error.value = uploadErrorMessage(
      e instanceof ImageFileError ? e.code : e?.response?.data?.error
    );
  } finally {
    isUploading.value = false;
    // allow re-selecting the same file
    if (fileInput.value) fileInput.value.value = '';
  }
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      class="flex items-center justify-center w-full overflow-hidden border rounded-lg h-28 border-n-weak bg-n-alpha-black1"
    >
      <img
        v-if="srcModel"
        :src="srcModel"
        :alt="altModel"
        class="object-contain max-w-full max-h-full"
      />
      <span v-else class="i-lucide-image size-6 text-n-slate-10" />
    </div>

    <button
      type="button"
      :disabled="isUploading || !campaignId"
      class="flex items-center justify-center w-full gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-n-weak bg-n-alpha-black1 text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
      @click="openPicker"
    >
      <span
        v-if="isUploading"
        class="i-lucide-loader-circle animate-spin size-4"
      />
      <span v-else class="i-lucide-upload size-4" />
      {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.IMAGE.REPLACE') }}
    </button>

    <input
      ref="fileInput"
      type="file"
      accept="image/*"
      class="hidden"
      @change="onFile"
    />

    <p v-if="error" class="text-xs text-n-ruby-11">{{ error }}</p>

    <label class="flex flex-col gap-1.5">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.IMAGE.URL') }}
      </span>
      <input
        :value="srcModel"
        type="text"
        spellcheck="false"
        class="w-full px-2.5 py-1.5 text-sm rounded-lg border border-n-weak bg-n-alpha-black1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:border-n-brand"
        @change="onSrcChange"
      />
    </label>

    <label class="flex flex-col gap-1.5">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.IMAGE.ALT') }}
      </span>
      <input
        :value="altModel"
        type="text"
        class="w-full px-2.5 py-1.5 text-sm rounded-lg border border-n-weak bg-n-alpha-black1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:border-n-brand"
        @change="onAltChange"
      />
    </label>

    <label class="flex flex-col gap-1.5">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.IMAGE.LINK') }}
      </span>
      <input
        :value="hrefModel"
        type="text"
        spellcheck="false"
        class="w-full px-2.5 py-1.5 text-sm rounded-lg border border-n-weak bg-n-alpha-black1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:border-n-brand"
        @change="onHrefChange"
      />
    </label>

    <button
      v-if="isVideoLink"
      type="button"
      :disabled="isFetchingPoster || !campaignId"
      class="flex items-center justify-center w-full gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-n-weak bg-n-alpha-black1 text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
      @click="fetchVideoPoster"
    >
      <span
        v-if="isFetchingPoster"
        class="i-lucide-loader-circle animate-spin size-4"
      />
      <span v-else class="i-lucide-clapperboard size-4" />
      {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.IMAGE.FETCH_POSTER') }}
    </button>
  </div>
</template>
