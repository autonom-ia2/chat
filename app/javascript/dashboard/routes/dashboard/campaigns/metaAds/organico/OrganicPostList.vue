<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { intlLocale, thumbClass } from '../metaAdsHelpers';

// Seus posts (#2199): os 3 posts do período com mais curtidas e comentários, cada um abrindo no Facebook ou no
// Instagram. Data numa linha e números em outra, para não quebrar no meio no celular.
defineProps({
  posts: { type: Array, required: true },
  days: { type: Number, required: true },
});

const { locale } = useI18n();

const format = value =>
  new Intl.NumberFormat(intlLocale(locale.value)).format(value);
const published = value =>
  new Date(value).toLocaleDateString(intlLocale(locale.value), {
    day: 'numeric',
    month: 'short',
  });

const failed = ref([]);
</script>

<template>
  <section class="flex flex-col gap-2" data-organic-top-posts>
    <h4 class="m-0 text-sm font-semibold text-n-slate-12">
      {{ $t('META_ADS_ORGANIC.TOP_POSTS.TITLE') }}
    </h4>
    <p
      v-if="!posts.length"
      data-organic-no-posts
      class="m-0 text-sm text-n-slate-11"
    >
      {{ $t('META_ADS_ORGANIC.TOP_POSTS.EMPTY', { days }) }}
    </p>
    <ol v-else class="m-0 flex list-none flex-col gap-1 p-0">
      <li v-for="post in posts" :key="post.id">
        <a
          :href="post.permalink"
          target="_blank"
          rel="noopener noreferrer"
          class="flex min-h-11 items-center gap-3 rounded-xl p-2 text-start no-underline hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        >
          <img
            v-if="post.image_url && !failed.includes(post.id)"
            :src="post.image_url"
            alt=""
            class="size-14 shrink-0 rounded-lg object-cover"
            @error="failed.push(post.id)"
          />
          <span
            v-else
            class="flex size-14 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br text-white"
            :class="thumbClass(post.id)"
            aria-hidden="true"
          >
            <span class="i-lucide-image size-5" />
          </span>
          <span class="flex min-w-0 flex-col gap-0.5">
            <span class="line-clamp-2 text-sm text-n-slate-12">{{
              post.text
            }}</span>
            <span class="text-sm text-n-slate-11">{{
              published(post.created_time)
            }}</span>
            <!-- No celular, um número por linha; a partir de 420 px, os dois na mesma linha com o ponto. Sem o alcance
                 do post (a Meta não deu), só as curtidas. -->
            <span
              class="flex flex-col text-sm text-n-slate-11 min-[420px]:flex-row min-[420px]:flex-wrap min-[420px]:gap-x-1.5"
            >
              <span v-if="post.reach != null" class="whitespace-nowrap">
                {{
                  $t('META_ADS_ORGANIC.TOP_POSTS.REACH', {
                    count: format(post.reach),
                  })
                }}
              </span>
              <!-- O ponto entre os números é enfeite (CSS), não texto. -->
              <span
                v-if="post.reach != null"
                aria-hidden="true"
                class="hidden before:content-['·'] min-[420px]:inline"
              />
              <span class="whitespace-nowrap">
                {{
                  $t('META_ADS_ORGANIC.TOP_POSTS.INTERACTIONS', {
                    count: format(post.interactions),
                  })
                }}
              </span>
            </span>
          </span>
        </a>
      </li>
    </ol>
  </section>
</template>
