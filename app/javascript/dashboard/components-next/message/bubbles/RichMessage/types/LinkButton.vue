<script setup>
// Botão de link: `{ type: 'link_button', label, url, header?, footer? }`, com o corpo em `content`.
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../../../provider.js';
import Frame from '../Frame.vue';
import ActionRow from '../ActionRow.vue';

const { contentAttributes } = useMessageContext();
const { t } = useI18n();
const addressId = useId();

// O rótulo e o endereço vêm de quem chamou a API: só texto entra na tela.
const textOf = value => (typeof value === 'string' ? value : '');

// A conversa pode ter mensagem antiga ou de outra origem: só endereço http ou https vira link, e o link usa
// o endereço já interpretado (`https:exemplo.com` cru seria um caminho relativo ao painel).
const httpHrefOf = value => {
  try {
    const parsed = new URL(value);
    return ['http:', 'https:'].includes(parsed.protocol) ? parsed.href : '';
  } catch (error) {
    return '';
  }
};

const richMessage = computed(() => contentAttributes.value?.richMessage ?? {});
const url = computed(() => textOf(richMessage.value.url));
const href = computed(() => httpHrefOf(url.value));
</script>

<template>
  <Frame
    bubble-name="rich-link-button"
    :header="textOf(richMessage.header)"
    :footer="textOf(richMessage.footer)"
  >
    <div class="flex flex-col gap-1.5">
      <ActionRow
        icon="i-lucide-external-link"
        :label="textOf(richMessage.label)"
        :href="href"
        :aria-describedby="addressId"
      />
      <div :id="addressId" class="text-xs text-n-slate-11 break-all">
        {{ t('RICH_MESSAGE.LINK_BUTTON.OPENS', { url }) }}
      </div>
    </div>
  </Frame>
</template>
