<script setup>
// #3082 — a conferência antes de apagar um campo. Apagar é "guardar escondido"
// (decisão do Rodrigo, 21/11/2026): o campo sai das telas e das IAs, e o que
// foi escrito nele fica guardado para trazer de volta.
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { t } = useI18n();
</script>

<template>
  <div data-apagar-campo class="flex flex-col gap-3">
    <div class="flex items-start gap-3 rounded-lg bg-n-slate-3 p-3">
      <Icon
        icon="i-lucide-eye-off"
        class="mt-0.5 size-5 shrink-0 text-n-slate-11"
      />
      <p class="text-sm leading-relaxed text-n-slate-12">
        {{ t('RELATIONSHIPS.DELETE.GONE') }}
      </p>
    </div>
    <div class="flex items-start gap-3 rounded-lg bg-n-teal-3 p-3">
      <Icon
        icon="i-lucide-archive"
        class="mt-0.5 size-5 shrink-0 text-n-teal-11"
      />
      <p class="text-sm leading-relaxed text-n-slate-12">
        {{ t('RELATIONSHIPS.DELETE.KEPT') }}
      </p>
    </div>
  </div>
</template>
