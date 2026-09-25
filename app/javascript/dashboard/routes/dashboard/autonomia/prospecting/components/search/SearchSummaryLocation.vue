<script setup>
// Frente de local: as linhas de local e tipo de área no resumo da busca.
import { useI18n } from 'vue-i18n';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import { formatAreaType } from '../../utils/searchFormatters';

const { t } = useI18n();
const { form, selectedLocationLabel } = useProspectingSearchContext();
</script>

<template>
  <div class="grid gap-1">
    <dt class="text-xs text-n-slate-10">
      {{ t('PROSPECTING.SEARCH.FIELDS.LOCATION') }}
    </dt>
    <dd class="break-words font-medium text-n-slate-12">
      {{ selectedLocationLabel || '-' }}
    </dd>
  </div>
  <div class="grid gap-1">
    <dt class="text-xs text-n-slate-10">
      {{ t('PROSPECTING.SEARCH.FIELDS.AREA_TYPE') }}
    </dt>
    <dd class="font-medium text-n-slate-12">
      {{ formatAreaType(form.area_type, t) }}
    </dd>
  </div>
</template>
