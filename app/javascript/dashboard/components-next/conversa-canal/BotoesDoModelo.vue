<script setup>
// O que o cliente vê de uma mensagem de modelo além do texto (#1702), como no app:
//   parte "topo"     — dentro do balão, antes do texto: a oferta por tempo limitado e o
//                      cartão do produto do catálogo;
//   parte "botoes"   — dentro do balão, depois da hora: um botão por linha, separados
//                      por um fio, na largura do balão;
//   parte "carrossel"— fora do balão, embaixo: os cartões lado a lado.
// Botão de link abre o endereço que o cliente recebeu (B2, Rodrigo em 17/10); os
// outros só mostram, com a dica de que o cliente toca no celular. Daqui não sai nada.
// Dentro do balão lê a mensagem do contexto; na lista recebe a mensagem por prop.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useMessageContext } from '../message/provider.js';
import { MESSAGE_STATUS } from '../message/constants';
import { usePele } from './pele';
import { useModeloDaMensagem } from './useModeloDaMensagem';

const props = defineProps({
  parte: {
    type: String,
    required: true,
    validator: v => ['topo', 'botoes', 'carrossel'].includes(v),
  },
  message: { type: Object, default: null },
});

const { t } = useI18n();
const pele = usePele();
const contexto = props.message ? null : useMessageContext();
const mensagem = computed(() =>
  props.message
    ? props.message
    : {
        additionalAttributes: contexto.additionalAttributes?.value,
        inboxId: contexto.inboxId?.value,
        status: contexto.status?.value,
      }
);
const { botoes, cartoes, oferta, produto } = useModeloDaMensagem(mensagem);
// Mensagem que não saiu: o cliente não recebeu botão nenhum.
const falhou = computed(() => mensagem.value.status === MESSAGE_STATUS.FAILED);
// A parte que aparece: nenhuma sem a pele ou com a mensagem que não saiu.
const parteVisivel = computed(() =>
  pele.value && !falhou.value ? props.parte : null
);

const LINHA =
  'flex items-center justify-center gap-1.5 min-h-11 -mx-[9px] w-[calc(100%+16px)] px-3 border-t border-[#0A0A0A]/10 dark:border-white/10 text-[#1A6B42] dark:text-[#6FD07E] text-[14.2px] font-medium';
const SOMBRA = 'shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]';
</script>

<template>
  <div
    v-if="parteVisivel === 'topo' && (oferta || produto)"
    class="flex flex-col gap-1.5 mb-1.5"
    data-topo-do-modelo
  >
    <div
      v-if="produto"
      class="flex items-center gap-3 p-2 rounded-md bg-[#0A0A0A]/5 dark:bg-[#000]/20"
    >
      <span
        class="grid place-content-center size-12 rounded bg-[#0A0A0A]/10 dark:bg-white/10"
      >
        <Icon icon="i-ph-storefront" class="size-6 opacity-70" />
      </span>
      <span class="text-[13px] font-medium">
        {{ t('CONVERSA_CANAL.MODELO.PRODUTO') }}
      </span>
    </div>
    <div
      v-if="oferta"
      class="flex items-start gap-2 p-2 rounded-md bg-[#0A0A0A]/5 dark:bg-[#000]/20"
    >
      <Icon icon="i-ph-timer-bold" class="size-5 mt-0.5 text-[#E53935]" />
      <span class="flex flex-col">
        <span class="text-[14px] font-medium break-words">
          {{
            oferta.limited_time_offer?.text || t('CONVERSA_CANAL.MODELO.OFERTA')
          }}
        </span>
        <span class="text-[12px] text-[#666666] dark:text-[#A7A8A8]">
          {{ t('CONVERSA_CANAL.MODELO.OFERTA') }}
        </span>
      </span>
    </div>
  </div>

  <div
    v-else-if="parteVisivel === 'botoes' && botoes.length"
    class="flex flex-col mt-1 -mb-[8px]"
    role="group"
    :aria-label="t('CONVERSA_CANAL.MODELO.BOTOES')"
    data-botoes-do-modelo
  >
    <template v-for="(botao, indice) in botoes" :key="indice">
      <a
        v-if="botao.endereco"
        :href="botao.endereco"
        target="_blank"
        rel="noopener noreferrer"
        :class="LINHA"
        class="hover:bg-[#0A0A0A]/5 dark:hover:bg-white/5"
        :data-tipo-do-botao="botao.tipo"
      >
        <Icon :icon="botao.icone" class="size-4 flex-shrink-0" />
        <span class="min-w-0 break-words">{{ botao.texto }}</span>
        <span class="sr-only">{{
          t('CONVERSA_CANAL.MODELO.ABRE_EM_OUTRA_ABA')
        }}</span>
      </a>
      <div
        v-else
        :class="LINHA"
        :title="t('CONVERSA_CANAL.MODELO.SO_NO_CELULAR')"
        :data-tipo-do-botao="botao.tipo"
      >
        <Icon :icon="botao.icone" class="size-4 flex-shrink-0" />
        <span class="min-w-0 break-words">{{ botao.texto }}</span>
      </div>
    </template>
  </div>

  <li
    v-else-if="parteVisivel === 'carrossel' && cartoes.length"
    class="list-none flex -mt-1 mb-2 ltr:ml-auto rtl:mr-auto ltr:mr-8 rtl:ml-8 max-w-full"
    data-carrossel-do-modelo
  >
    <div
      class="flex gap-2 max-w-[min(100%,640px)] overflow-x-auto pb-1 snap-x"
      tabindex="0"
      :aria-label="t('CONVERSA_CANAL.MODELO.CARROSSEL')"
    >
      <div
        v-for="(cartao, indice) in cartoes"
        :key="indice"
        class="flex flex-col flex-shrink-0 w-56 p-[3px] snap-start rounded-[10px] bg-[#D9FDD3] dark:bg-[#144D37] text-[#0A0A0A] dark:text-[#FAFAFA]"
        :class="SOMBRA"
      >
        <div
          class="grid place-content-center h-32 rounded-[8px] bg-[#0A0A0A]/10 dark:bg-[#000]/20"
        >
          <Icon :icon="cartao.midia" class="size-8 opacity-60" />
        </div>
        <p class="px-1.5 pt-1.5 pb-1 text-[14px] leading-[19px] break-words">
          {{ cartao.texto }}
        </p>
        <div
          v-for="(botao, i) in cartao.botoes"
          :key="i"
          class="flex items-center justify-center gap-1.5 min-h-11 border-t border-[#0A0A0A]/10 dark:border-white/10 text-[#1A6B42] dark:text-[#6FD07E] text-[14px] font-medium"
        >
          <Icon :icon="botao.icone" class="size-4" />
          {{ botao.texto }}
        </div>
      </div>
    </div>
  </li>
  <!-- Sem a pele, ou com a mensagem que não saiu: não mostra nada. -->
  <template v-else />
</template>
