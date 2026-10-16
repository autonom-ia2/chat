<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import Button from 'dashboard/components-next/button/Button.vue';
import StoreServiceIcon from './StoreServiceIcon.vue';
import { formatMoney } from '../helpers';
import { useStoreLabels } from '../composables/useStoreLabels';

const props = defineProps({ item: { type: Object, required: true } });
defineEmits(['details']);
const { t } = useI18n();
const labels = useStoreLabels();
const { resolvedLocale } = useLocale();
const offer = computed(() => props.item.offers[0]);
</script>

<template>
  <article
    class="flex flex-col min-w-0 gap-4 p-4 border rounded-lg border-n-weak bg-n-solid-1"
  >
    <div class="flex items-start gap-3 min-w-0">
      <StoreServiceIcon :item="item" />
      <div class="min-w-0">
        <h3 class="text-base font-medium break-words text-n-slate-12">
          {{ item.service.name }}
        </h3>
        <span class="text-xs text-n-slate-11">{{
          labels.groups[item.group]
        }}</span>
      </div>
    </div>
    <p class="flex-1 m-0 text-sm break-words text-n-slate-11">
      {{ item.service.description }}
    </p>
    <div v-if="offer" class="min-w-0">
      <p class="m-0 text-xs break-words text-n-slate-11">
        {{ offer.plan.name }}
      </p>
      <p class="m-0 mt-1 text-base font-semibold text-n-slate-12">
        {{
          formatMoney(offer.price.price, offer.price.currency, resolvedLocale)
        }}
        <span class="text-xs font-normal text-n-slate-11">{{
          labels.cycles[offer.price.billingCycle]
        }}</span>
      </p>
    </div>
    <Button
      :label="t('FINANCIAL.STORE.DETAILS')"
      icon="i-lucide-arrow-up-right"
      variant="outline"
      color="slate"
      @click="$emit('details', item)"
    />
  </article>
</template>
