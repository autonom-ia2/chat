<script setup>
import { useI18n } from 'vue-i18n';
import {
  REVIEWS_MAX,
  leadReviews,
  reviewAuthor,
  reviewText,
  reviewTime,
} from '../../utils/leadDetail';

defineProps({
  lead: { type: Object, required: true },
});

const { t } = useI18n();
</script>

<template>
  <div class="rounded-md border border-n-weak bg-n-solid-2 p-4">
    <h3 class="text-xs font-semibold uppercase tracking-wide text-n-slate-10">
      {{
        t('PROSPECTING.SEARCH.LATEST_REVIEWS_TITLE', {
          count: REVIEWS_MAX,
        })
      }}
    </h3>
    <ul class="mt-3 grid gap-3">
      <li
        v-for="(review, index) in leadReviews(lead)"
        :key="review.name || review.publishTime || index"
        class="border-b border-n-weak pb-3 last:border-b-0 last:pb-0"
      >
        <div class="flex flex-wrap items-center gap-2">
          <span
            v-if="review.rating"
            class="inline-flex items-center gap-1 text-xs font-semibold text-amber-600"
          >
            <span class="i-lucide-star size-3 fill-current" />
            {{ review.rating }}
          </span>
          <span
            v-if="reviewAuthor(review)"
            class="text-xs font-medium text-n-slate-11"
          >
            {{ reviewAuthor(review) }}
          </span>
          <span v-if="reviewTime(review)" class="text-xs text-n-slate-9">
            {{ reviewTime(review) }}
          </span>
        </div>
        <p
          class="mt-1 whitespace-pre-line break-words text-sm leading-relaxed text-n-slate-11"
        >
          {{ reviewText(review) }}
        </p>
      </li>
    </ul>
  </div>
</template>
