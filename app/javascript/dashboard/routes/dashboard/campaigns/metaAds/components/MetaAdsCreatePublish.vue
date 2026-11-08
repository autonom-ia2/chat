<script setup>
import { computed } from 'vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import { enviarMidiaDoPost } from '../criacaoNaMeta';
import { lugarDoPost } from '../criarPost';
import MetaAdsAdPreview from './MetaAdsAdPreview.vue';
import MetaAdsMediaPicker from './MetaAdsMediaPicker.vue';

// Anúncios da Meta (#2198 PR 3, #2653), criar post: a Página (só quando há mais de uma), onde publicar (as redes que
// dão já vêm marcadas), a foto ou o vídeo e a legenda, com a prévia do post ao lado. Rede que não dá aparece apagada,
// com o motivo (`reasons`). Publicar não gasta nada.
const props = defineProps({
  pages: { type: Array, default: () => [] },
  pageName: { type: String, default: '' },
  // { username, publish_left } da Página escolhida, ou null.
  instagram: { type: Object, default: null },
  // { instagram: 'NO_INSTAGRAM' | 'LIMIT' | 'NO_PERMISSION', facebook: 'NO_PERMISSION' }: só as que não dão.
  reasons: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['uploading']);

const post = defineModel({ type: Object, required: true });

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.PUBLISH';

const NETWORKS = [
  { value: 'instagram', icon: 'i-ri-instagram-line' },
  { value: 'facebook', icon: 'i-ri-facebook-circle-line' },
];

const pageOptions = computed(() =>
  props.pages.map(page => ({ value: page.id, label: page.name }))
);

const nameFor = network =>
  network === 'instagram'
    ? props.instagram && `@${props.instagram.username}`
    : props.pageName;

const toggle = network => {
  if (props.reasons[network]) return;
  const networks = post.value.networks.includes(network)
    ? post.value.networks.filter(item => item !== network)
    : [...post.value.networks, network];
  post.value = { ...post.value, networks };
};

// Sobe para o nosso armazenamento (o post não usa a conta de anúncios): a mídia leva o id que o publicar usa.
const upload = async (media, file) => {
  const sent = await enviarMidiaDoPost(file);
  return { ...media, signed_id: sent.signed_id };
};

const places = computed(() => lugarDoPost(post.value.networks));
</script>

<template>
  <div
    class="grid min-w-0 grid-cols-1 gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]"
  >
    <div class="flex min-w-0 flex-col gap-5">
      <div v-if="pages.length > 1" class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t(`${KEY}.PAGE`) }}
        </span>
        <ChoiceSelect
          :model-value="post.page_id"
          data-create-publish-page
          :options="pageOptions"
          :aria-label="$t(`${KEY}.PAGE`)"
          :placeholder="$t(`${KEY}.CHOOSE_PAGE`)"
          class="w-full"
          @update:model-value="post = { ...post, page_id: $event }"
        />
      </div>
      <fieldset class="m-0 flex min-w-0 flex-col gap-2 border-0 p-0">
        <legend class="mb-2 p-0 text-sm font-medium text-n-slate-12">
          {{ $t(`${KEY}.WHERE`) }}
        </legend>
        <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <button
            v-for="network in NETWORKS"
            :key="network.value"
            type="button"
            role="checkbox"
            :aria-checked="post.networks.includes(network.value)"
            :aria-disabled="Boolean(reasons[network.value]) || undefined"
            :data-create-publish-network="network.value"
            class="flex min-h-11 items-start gap-3 rounded-xl border-0 p-3 text-start focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :class="[
              post.networks.includes(network.value)
                ? 'bg-n-brand/10 ring-2 ring-n-brand'
                : 'bg-n-solid-1 ring-1 ring-n-weak',
              reasons[network.value] ? 'cursor-not-allowed' : '',
            ]"
            @click="toggle(network.value)"
          >
            <span
              :class="[
                post.networks.includes(network.value)
                  ? 'i-lucide-square-check'
                  : 'i-lucide-square',
                reasons[network.value] ? 'opacity-60' : '',
              ]"
              class="mt-0.5 size-5 shrink-0 text-n-brand"
              aria-hidden="true"
            />
            <span class="flex min-w-0 flex-col gap-0.5">
              <span
                class="flex items-center gap-1.5 text-sm font-semibold text-n-slate-12"
                :class="reasons[network.value] ? 'opacity-60' : ''"
              >
                <span :class="network.icon" class="size-4" aria-hidden="true" />
                {{ $t(`${KEY}.NETWORKS.${network.value.toUpperCase()}`) }}
              </span>
              <span
                :data-create-publish-reason="reasons[network.value]"
                class="break-words text-xs text-n-slate-11"
              >
                {{
                  reasons[network.value]
                    ? $t(`${KEY}.REASONS.${reasons[network.value]}`)
                    : nameFor(network.value)
                }}
              </span>
            </span>
          </button>
        </div>
      </fieldset>
      <MetaAdsMediaPicker
        :model-value="post.media"
        :upload="upload"
        @update:model-value="post = { ...post, media: $event }"
        @uploading="emit('uploading', $event)"
      />
      <TextArea
        :model-value="post.caption"
        data-create-caption
        :label="$t(`${KEY}.CAPTION`)"
        :placeholder="$t(`${KEY}.CAPTION_PLACEHOLDER`)"
        :max-length="2200"
        show-character-count
        min-height="6rem"
        custom-text-area-wrapper-class="min-w-0"
        @update:model-value="post = { ...post, caption: $event }"
      />
    </div>
    <MetaAdsAdPreview
      :page-name="
        places === 'INSTAGRAM' ? nameFor('instagram') : nameFor('facebook')
      "
      :text="post.caption"
      :media="post.media"
      :places="places"
      feed-only
      organic
    />
  </div>
</template>
