<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { lugarDoPost } from '../criarPost';
import MetaAdsAdPreview from './MetaAdsAdPreview.vue';

// Anúncios da Meta (#2198 PR 3, #2653), criar post: conferir e publicar. Publicar é público na hora: a confirmação diz onde e
// que, para tirar, é no app. "Publicar e impulsionar" publica e segue para quem vê e quanto investir; o
// impulsionamento nasce pausado.
const props = defineProps({
  // { networks, media, caption }
  post: { type: Object, required: true },
  pageName: { type: String, default: '' },
  instagram: { type: Object, default: null },
  saving: { type: Boolean, default: false },
});

const emit = defineEmits(['publish']);

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.PUBLISH_REVIEW';
const dialog = ref(null);
const boost = ref(false);

const places = computed(() => lugarDoPost(props.post.networks));

const open = withBoost => {
  boost.value = withBoost;
  dialog.value?.open();
};
const close = () => dialog.value?.close();

defineExpose({ open, close });
</script>

<template>
  <div
    data-create-publish-review
    class="grid min-w-0 grid-cols-1 gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]"
  >
    <div class="flex min-w-0 flex-col gap-4">
      <dl class="m-0 grid gap-3">
        <div class="flex flex-col gap-1 rounded-xl bg-n-alpha-1 p-4">
          <dt class="text-xs font-semibold text-n-slate-11">
            {{ $t(`${KEY}.WHERE`) }}
          </dt>
          <dd data-create-publish-where class="m-0 text-sm text-n-slate-12">
            {{
              $t(`${KEY}.PLACES.${places}`, {
                page: pageName,
                username: instagram?.username,
              })
            }}
          </dd>
        </div>
        <div class="flex flex-col gap-1 rounded-xl bg-n-alpha-1 p-4">
          <dt class="text-xs font-semibold text-n-slate-11">
            {{ $t(`${KEY}.CAPTION`) }}
          </dt>
          <dd
            class="m-0 whitespace-pre-line break-words text-sm text-n-slate-12"
          >
            {{ post.caption || $t(`${KEY}.NO_CAPTION`) }}
          </dd>
        </div>
      </dl>
      <p
        data-create-publish-free
        class="m-0 flex gap-2 rounded-xl bg-n-teal-2 p-3 text-sm text-n-teal-12"
      >
        <span
          class="i-lucide-circle-check mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ $t(`${KEY}.FREE`) }}
      </p>
    </div>
    <MetaAdsAdPreview
      :page-name="places === 'INSTAGRAM' ? `@${instagram?.username}` : pageName"
      :text="post.caption"
      :media="post.media"
      :places="places"
      feed-only
      organic
    />

    <Dialog
      ref="dialog"
      type="alert"
      :title="$t(`${KEY}.CONFIRM_TITLE.${places}`)"
      :description="
        $t(boost ? `${KEY}.CONFIRM_HINT_BOOST` : `${KEY}.CONFIRM_HINT`)
      "
      :is-loading="saving"
      @confirm="emit('publish', boost)"
    >
      <template #footer>
        <div
          class="flex w-full flex-col-reverse gap-3 sm:flex-row sm:items-center"
        >
          <Button
            variant="faded"
            color="slate"
            :label="$t(`${KEY}.CANCEL`)"
            class="w-full sm:flex-1"
            type="button"
            @click="close"
          />
          <Button
            data-create-publish-confirm
            :label="$t(`${KEY}.CONFIRM`)"
            class="w-full sm:flex-1"
            :is-loading="saving"
            :disabled="saving"
            type="submit"
          />
        </div>
      </template>
    </Dialog>
  </div>
</template>
