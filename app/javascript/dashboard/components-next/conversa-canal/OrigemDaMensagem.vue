<script setup>
// De onde veio a mensagem do cliente (#1702), no topo do balão dele, como citação do
// app: faixa à esquerda, o que foi citado e a miniatura à direita; o texto vem embaixo.
//   anúncio click-to-WhatsApp (`content_attributes.referral`): "Anúncio", o título e a
//     miniatura; o toque abre o anúncio em outra aba (só http(s));
//   pergunta sobre produto do catálogo (`content_attributes.referred_product`, gravado
//     no recebimento): "Produto do catálogo", o nome (ou o código) e a foto.
// Sem a pele, o anúncio segue no cartão de sempre, fora do balão (WhatsappReferral).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useMessageContext } from '../message/provider.js';
import { MESSAGE_VARIANTS } from '../message/constants';
import { enderecoDoBotao } from './useModeloDaMensagem';

const { t } = useI18n();
const { variant, contentAttributes } = useMessageContext();

const doCliente = computed(() => variant?.value === MESSAGE_VARIANTS.USER);

const anuncio = computed(() => {
  const referral = doCliente.value ? contentAttributes?.value?.referral : null;
  if (!referral) return null;
  return {
    titulo: referral.headline || '',
    texto: referral.body || '',
    endereco: enderecoDoBotao(referral.sourceUrl),
    // Do vídeo, só a miniatura: o vídeo inteiro não cabe na citação.
    foto: enderecoDoBotao(referral.thumbnailUrl || referral.imageUrl),
    video: referral.mediaType === 'video',
  };
});

const produto = computed(() => {
  const citado = doCliente.value
    ? contentAttributes?.value?.referredProduct
    : null;
  if (!citado?.productRetailerId) return null;
  return {
    nome: citado.nome || '',
    codigo: citado.productRetailerId,
    preco: citado.preco || '',
    foto: enderecoDoBotao(citado.fotoUrl),
  };
});

const CITACAO =
  'flex w-full min-w-0 mb-1 overflow-hidden text-start rounded-[7.5px] border-s-4 border-s-[#5E44D8] dark:border-s-[#B3A1FF] bg-[#000]/[0.05] dark:bg-[#000]/20 text-current no-underline hover:no-underline';
const ROTULO =
  'flex items-center gap-1 text-[12.8px] leading-[20px] font-medium text-[#5E44D8] dark:text-[#B3A1FF]';
const TEXTO =
  'block text-[13px] leading-[18px] text-[#666666] dark:text-[#B5C2BC] break-words';
</script>

<template>
  <component
    :is="anuncio.endereco ? 'a' : 'div'"
    v-if="anuncio"
    :href="anuncio.endereco || undefined"
    :target="anuncio.endereco ? '_blank' : undefined"
    :rel="anuncio.endereco ? 'noopener noreferrer' : undefined"
    :class="CITACAO"
    data-citacao-do-anuncio
  >
    <span class="flex-1 min-w-0 px-2 py-1.5">
      <span :class="ROTULO">
        <Icon icon="i-ph-megaphone-simple" class="size-3.5 flex-shrink-0" />
        {{ t('CONVERSA_CANAL.ORIGEM.ANUNCIO') }}
        <span v-if="anuncio.endereco" class="sr-only">
          {{ t('CONVERSA_CANAL.ORIGEM.ABRIR_ANUNCIO') }}
        </span>
      </span>
      <span
        v-if="anuncio.titulo"
        class="block text-[13px] leading-[18px] font-medium break-words line-clamp-2"
      >
        {{ anuncio.titulo }}
      </span>
      <span v-if="anuncio.texto" :class="TEXTO" class="line-clamp-2">
        {{ anuncio.texto }}
      </span>
    </span>
    <span v-if="anuncio.foto" class="relative shrink-0 size-[60px]">
      <img
        :src="anuncio.foto"
        alt=""
        class="size-full object-cover skip-context-menu"
      />
      <Icon
        v-if="anuncio.video"
        icon="i-ph-play-fill"
        class="absolute inset-0 m-auto size-5 text-white drop-shadow"
      />
    </span>
  </component>

  <div v-if="produto" :class="CITACAO" data-citacao-do-produto>
    <span class="flex-1 min-w-0 px-2 py-1.5">
      <span :class="ROTULO">
        <Icon icon="i-ph-storefront" class="size-3.5 flex-shrink-0" />
        {{ t('CONVERSA_CANAL.ORIGEM.PRODUTO') }}
      </span>
      <span class="block text-[13px] leading-[18px] font-medium break-words">
        {{
          produto.nome ||
          t('CONVERSA_CANAL.ORIGEM.CODIGO', { codigo: produto.codigo })
        }}
      </span>
      <span v-if="produto.preco" :class="TEXTO">{{ produto.preco }}</span>
    </span>
    <img
      v-if="produto.foto"
      :src="produto.foto"
      alt=""
      class="size-[60px] object-cover shrink-0 skip-context-menu"
    />
  </div>
</template>
