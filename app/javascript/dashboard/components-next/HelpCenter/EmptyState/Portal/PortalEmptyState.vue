<script setup>
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import ArticleCard from 'dashboard/components-next/HelpCenter/ArticleCard/ArticleCard.vue';
import articleContent from './portalEmptyStateContent';
</script>

<template>
  <EmptyStateLayout
    :title="$t('HELP_CENTER.TITLE')"
    :subtitle="$t('HELP_CENTER.NEW_PAGE.DESCRIPTION')"
    class="bg-n-surface-1"
  >
    <template #empty-state-item>
      <div class="grid grid-cols-2 gap-4 p-px">
        <div class="space-y-4">
          <ArticleCard
            v-for="(article, index) in articleContent"
            :id="article.id"
            :key="`article-${index}`"
            :title="article.title"
            :status="article.status"
            :updated-at="article.updatedAt"
            :author="article.author"
            :category="article.category"
            :views="article.views"
          />
        </div>
        <div class="space-y-4">
          <ArticleCard
            v-for="(article, index) in articleContent.reverse()"
            :id="article.id"
            :key="`article-${index}`"
            :title="article.title"
            :status="article.status"
            :updated-at="article.updatedAt"
            :author="article.author"
            :category="article.category"
            :views="article.views"
          />
        </div>
      </div>
    </template>
  </EmptyStateLayout>
</template>
