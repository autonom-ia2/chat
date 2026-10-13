<script setup>
// Um botão como o cliente o vê. Com `href` o atendente abre o endereço em outra aba; sem ele é só a imagem do botão.
// Slot padrão no lugar do rótulo (ex.: título e descrição) e slot `trailing` à direita (ex.: opção escolhida).
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

defineProps({
  label: { type: String, required: true },
  icon: { type: String, default: '' },
  href: { type: String, default: '' },
});

const { t } = useI18n();
</script>

<template>
  <a
    v-if="href"
    :href="href"
    target="_blank"
    rel="noopener noreferrer"
    class="flex items-center justify-center gap-2 w-full min-h-11 bg-n-solid-3 px-4 py-2 rounded-lg text-sm text-center text-n-slate-12 border border-n-container hover:bg-n-alpha-2"
  >
    <Icon v-if="icon" :icon="icon" class="size-4 flex-shrink-0" />
    <span class="min-w-0 break-words">
      <slot>{{ label }}</slot>
      <span class="sr-only">
        {{ t('RICH_MESSAGE.ACTION_ROW.OPENS_IN_NEW_TAB') }}
      </span>
    </span>
    <slot name="trailing" />
  </a>
  <div
    v-else
    class="flex items-center justify-center gap-2 w-full min-h-9 bg-n-solid-3 px-4 py-2 rounded-lg text-sm text-center text-n-slate-12 border border-n-container"
  >
    <Icon v-if="icon" :icon="icon" class="size-4 flex-shrink-0" />
    <span class="min-w-0 break-words">
      <slot>{{ label }}</slot>
    </span>
    <slot name="trailing" />
  </div>
</template>
