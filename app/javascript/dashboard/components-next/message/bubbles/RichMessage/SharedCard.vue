<script setup>
// Cartão de algo compartilhado com o cliente (P5: localização e contato), no mesmo desenho do anexo de
// localização e de contato que o cliente manda (bubbles/BaseAttachment.vue): ícone, "<quem> compartilhou …",
// título e detalhe. Diferenças: título e detalhe quebram linha em vez de cortar, a ação é opcional e, quando
// existe, é um ActionRow com endereço (abre em outra aba, alvo de toque de 44 px).
import Icon from 'next/icon/Icon.vue';
import BaseBubble from '../Base.vue';
import ActionRow from './ActionRow.vue';

defineProps({
  bubbleName: { type: String, required: true },
  icon: { type: String, required: true },
  iconBgColor: { type: String, required: true },
  heading: { type: String, default: '' },
  title: { type: String, default: '' },
  detail: { type: String, default: '' },
  actionLabel: { type: String, default: '' },
  actionHref: { type: String, default: '' },
});
</script>

<template>
  <BaseBubble class="p-3" :data-bubble-name="bubbleName">
    <div class="grid gap-4 min-w-64">
      <div class="grid gap-3">
        <div
          class="size-8 rounded-lg grid place-content-center"
          :class="iconBgColor"
        >
          <Icon :icon="icon" class="text-white size-4" />
        </div>
        <div class="space-y-1 min-w-0">
          <div v-if="heading" class="text-sm text-n-slate-12 break-words">
            {{ heading }}
          </div>
          <div v-if="title" class="text-sm text-n-slate-12 break-words">
            {{ title }}
          </div>
          <div v-if="detail" class="text-sm text-n-slate-11 break-words">
            {{ detail }}
          </div>
        </div>
      </div>
      <ActionRow
        v-if="actionLabel && actionHref"
        :label="actionLabel"
        :href="actionHref"
      />
    </div>
  </BaseBubble>
</template>
