<script setup>
// Frente de local: as linhas de local e tipo de área no resumo da busca.
import { useI18n } from 'vue-i18n';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';

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
      {{
        form.area_type === 'viewport'
          ? t('PROSPECTING.SEARCH.AREA_VIEWPORT_SHORT')
          : t('PROSPECTING.SEARCH.AREA_RADIUS')
      }}
    </dd>
  </div>
</template>
