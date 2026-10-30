<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { intlLocale } from '../metaAdsHelpers';

// Anúncios da Meta (#2161): o post da Página por trás do anúncio, embaixo da imagem. O texto que as pessoas leem e
// o que elas fizeram com ele na Página (curtidas, comentários, compartilhamentos), com o caminho para o post no
// Facebook. Ajuda a decidir "trocar a imagem ou o texto", que o consultor sugere.
const props = defineProps({
  post: { type: Object, required: true },
});

const { locale } = useI18n();

const KEY = 'CRM_KANBAN.META_ADS_HUB.GESTAO.POST';

const published = computed(() =>
  props.post.created_time
    ? new Date(props.post.created_time).toLocaleDateString(
        intlLocale(locale.value),
        { day: 'numeric', month: 'short', year: 'numeric' }
      )
    : null
);

const numbers = computed(() => [
  { key: 'REACTIONS', icon: 'i-lucide-thumbs-up', value: props.post.reactions },
  {
    key: 'COMMENTS',
    icon: 'i-lucide-message-circle',
    value: props.post.comments,
  },
  { key: 'SHARES', icon: 'i-lucide-share-2', value: props.post.shares },
]);
</script>

<template>
  <section
    data-ad-post
    class="flex flex-col gap-3 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak"
  >
    <div class="flex flex-col gap-0.5">
      <h4 class="m-0 text-sm font-semibold text-n-slate-11">
        {{ $t(`${KEY}.TITLE`) }}
      </h4>
      <p v-if="post.page_name && published" class="m-0 text-xs text-n-slate-10">
        {{ $t(`${KEY}.WHERE`, { page: post.page_name, date: published }) }}
      </p>
    </div>
    <p
      v-if="post.message"
      data-ad-post-message
      class="m-0 whitespace-pre-line text-pretty text-base leading-relaxed text-n-slate-12"
    >
      {{ post.message }}
    </p>
    <ul
      data-ad-post-numbers
      class="m-0 flex list-none flex-wrap gap-x-5 gap-y-1 p-0 text-sm text-n-slate-11"
    >
      <li
        v-for="item in numbers"
        :key="item.key"
        class="inline-flex items-center gap-1.5 tabular-nums"
      >
        <span :class="item.icon" class="size-4" aria-hidden="true" />
        {{
          $t(`${KEY}.${item.key}`, { count: item.value || 0 }, item.value || 0)
        }}
      </li>
    </ul>
    <a
      v-if="post.permalink_url"
      :href="post.permalink_url"
      target="_blank"
      rel="noopener noreferrer"
      data-ad-post-link
      class="inline-flex min-h-11 items-center gap-1.5 self-start rounded-xl text-sm font-medium text-n-blue-11 no-underline hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
    >
      {{ $t(`${KEY}.OPEN`) }}
      <span class="i-lucide-external-link size-3.5" aria-hidden="true" />
    </a>
  </section>
</template>
