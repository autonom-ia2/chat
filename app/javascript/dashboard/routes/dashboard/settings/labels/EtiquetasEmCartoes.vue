<script setup>
// Configurações › Etiquetas no celular (abaixo de `md`), #1823: a tabela ficava
// mais larga que a tela e cortava Cor e Ações. Um cartão por etiqueta; em `md` ou
// mais a tabela de sempre continua (o BaseTable compartilhado não muda). Só com a
// flag `etiquetas_do_whatsapp`.
import Button from 'dashboard/components-next/button/Button.vue';
import NomeDaEtiquetaCelula from './NomeDaEtiquetaCelula.vue';

defineProps({
  items: { type: Array, default: () => [] },
  loading: { type: Object, default: () => ({}) },
  noDataMessage: { type: String, default: '' },
});

const emit = defineEmits(['editar', 'apagar']);
</script>

<template>
  <ul class="flex flex-col gap-3 m-0 p-0 list-none">
    <li
      v-for="label in items"
      :key="label.title"
      class="flex flex-col gap-3 p-4 rounded-xl border border-n-weak bg-n-solid-1"
    >
      <NomeDaEtiquetaCelula :titulo="label.title" />
      <p
        v-if="label.description"
        class="m-0 text-body-main text-n-slate-11 break-words"
      >
        {{ label.description }}
      </p>
      <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-2 min-w-0">
          <span
            class="size-4 flex-shrink-0 border border-solid rounded border-n-weak"
            :style="{ backgroundColor: label.color }"
          />
          <span class="text-body-main text-n-slate-12 truncate">
            {{ label.color }}
          </span>
        </div>
        <div class="flex gap-2 flex-shrink-0">
          <Button
            icon="i-woot-edit-pen"
            slate
            :aria-label="$t('LABEL_MGMT.FORM.EDIT')"
            :is-loading="loading[label.id]"
            class="!size-11"
            @click="emit('editar', label)"
          />
          <Button
            icon="i-woot-bin"
            slate
            :aria-label="$t('LABEL_MGMT.FORM.DELETE')"
            :is-loading="loading[label.id]"
            class="!size-11 hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
            @click="emit('apagar', label)"
          />
        </div>
      </div>
    </li>
    <li
      v-if="!items.length && noDataMessage"
      class="py-20 text-center text-body-main text-n-slate-11"
    >
      {{ noDataMessage }}
    </li>
  </ul>
</template>
