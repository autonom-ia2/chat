<script setup>
// Cartão de algo compartilhado com o cliente (P5: localização e contato), no mesmo desenho do anexo de
// localização e de contato que o cliente manda (bubbles/BaseAttachment.vue): ícone, "<quem> compartilhou …",
// título e detalhe. Diferenças: título e detalhe quebram linha em vez de cortar, a ação é opcional e, quando
// existe, é um ActionRow com endereço (abre em outra aba, alvo de toque de 44 px).
import Icon from 'next/icon/Icon.vue';
import BaseBubble from '../Base.vue';
import ActionRow from './ActionRow.vue';
import MapaDoWhatsapp from '../../../conversa-canal/midia/MapaDoWhatsapp.vue';

defineProps({
  bubbleName: { type: String, required: true },
  icon: { type: String, required: true },
  iconBgColor: { type: String, required: true },
  heading: { type: String, default: '' },
  title: { type: String, default: '' },
  detail: { type: String, default: '' },
  // Texto livre de quem compartilhou (a legenda da localização ao vivo), abaixo do detalhe.
  note: { type: String, default: '' },
  actionLabel: { type: String, default: '' },
  actionHref: { type: String, default: '' },
  // #1702: "lat,long" da localização; com a pele do WhatsApp, vira a miniatura do mapa.
  mapa: { type: String, default: '' },
  // #1709: uma linha a mais embaixo do detalhe (ex.: "Localização em tempo real"), só com a pele.
  aviso: { type: String, default: '' },
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
          <MapaDoWhatsapp v-if="mapa" :ponto="mapa" />
        </div>
        <div class="space-y-1 min-w-0">
          <div v-if="heading" class="text-sm text-n-slate-12 break-words">
            {{ heading }}
          </div>
          <div
            v-if="title"
            class="text-sm text-n-slate-12 break-words"
            data-titulo-do-cartao
          >
            {{ title }}
          </div>
          <div v-if="detail" class="text-sm text-n-slate-11 break-words">
            {{ detail }}
          </div>
          <div
            v-if="aviso"
            class="flex items-center gap-1 text-[13px] text-[#666666] dark:text-[#A7A8A8]"
            data-aviso-do-cartao
          >
            <span class="i-ph-broadcast size-4 shrink-0" aria-hidden="true" />
            {{ aviso }}
          </div>
          <div
            v-if="note"
            class="text-sm text-n-slate-12 break-words whitespace-pre-line"
          >
            {{ note }}
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
