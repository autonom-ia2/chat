<script setup>
// Álbum no balão com a cara do WhatsApp (#1702): fotos e vídeos mandados juntos num
// mosaico só. 2 lado a lado; 3 = uma grande em cima e duas embaixo; 4 em grade 2x2;
// mais de 4, a grade 2x2 com "+N" escurecido sobre a 4ª. Cada quadro é um botão que
// abre a galeria naquele item. A hora e os tiques ficam no canto, por cima do mosaico;
// com legenda, a legenda vem embaixo do mosaico e a hora no fim dela, como no app.
// Citação de um item do álbum rola até o quadro dele e o destaca por um instante.
// Chegando (#1831): o balão já aparece com "Recebendo fotos…" e quadros reservados, que
// as fotos preenchem sem tirar nenhum quadro do lugar (quadrosDoAlbum).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTimeoutFn } from '@vueuse/core';
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import FormattedContent from '../../message/bubbles/Text/FormattedContent.vue';
import BaseBubble from '../../message/bubbles/Base.vue';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import {
  provideMessageContext,
  useMessageContext,
} from '../../message/provider.js';
import { ATTACHMENT_TYPES, MESSAGE_VARIANTS } from '../../message/constants';
import {
  atributosDoAlbum,
  legendasDoAlbum,
  quadrosDoAlbum,
  tiqueDoAlbum,
} from './agruparAlbuns';
import {
  useAlbumDaMensagem,
  useAlbumEmQuadrados,
  useChegadaDoAlbum,
} from './useAlbuns';

const { t } = useI18n();
const contexto = useMessageContext();
const { filteredCurrentChatAttachments } = contexto;
// O balão é o 1º item; os outros vêm da lista de mensagens (useAlbunsDaConversa).
const album = useAlbumDaMensagem(contexto.id);
const itens = computed(() => album.value || []);
const chegada = useChegadaDoAlbum(contexto.id);
const emQuadrados = useAlbumEmQuadrados(contexto.id);

// A hora é a do último item e o tique é o do item mais atrasado, como no app. As
// reações de todos os itens aparecem juntas no selo do álbum. Chegando sem foto, o
// balão é o do marcador (não suportada): ganha a cor de mensagem do cliente.
provideMessageContext({
  ...contexto,
  variant: computed(() =>
    chegada.value?.noMarcador ? MESSAGE_VARIANTS.USER : contexto.variant.value
  ),
  createdAt: computed(
    () => itens.value.at(-1)?.createdAt ?? contexto.createdAt.value
  ),
  status: computed(() => tiqueDoAlbum(itens.value)),
  contentAttributes: computed(() => atributosDoAlbum(itens.value)),
});

const legendas = computed(() => legendasDoAlbum(itens.value));
// Lido uma vez pelo balão (Base.vue): com legenda, a hora sai de cima da foto.
const nomeDoBalao = legendas.value.length ? 'album-legenda' : 'album';

// Citação de um item: a conversa rola até o quadro (id "message<id>") e ele pisca.
const DESTAQUE_EM_MS = 1500;
const destacado = ref(null);
const { start: apagarDestaque } = useTimeoutFn(
  () => {
    destacado.value = null;
  },
  DESTAQUE_EM_MS,
  { immediate: false }
);
useEmitter(BUS_EVENTS.SCROLL_TO_MESSAGE, ({ messageId } = {}) => {
  if (!itens.value.some(item => item.id === messageId)) return;
  destacado.value = messageId;
  apagarDestaque();
});
// O 1º item já tem o id no balão da mensagem; os outros ganham no quadro.
const idDoQuadro = (item, posicao) =>
  posicao === 0 ? undefined : `message${item.id}`;

const mosaico = computed(() =>
  quadrosDoAlbum(itens.value, {
    emQuadrados: emQuadrados.value,
    chegando: !!chegada.value,
  })
);
const total = computed(() => itens.value.length);
const rotuloDoGrupo = computed(() =>
  chegada.value
    ? t('CONVERSA_CANAL.ALBUM.ROTULO_CHEGANDO', { n: total.value })
    : t('CONVERSA_CANAL.ALBUM.ROTULO', { total: total.value })
);

// Classes literais por quantidade e posição (o Tailwind só gera o que lê no código).
// Em quadrados (álbum do marcador): o próximo entra no fim e ninguém se mexe.
const formato = posicao => {
  if (mosaico.value.emQuadrados) return 'aspect-square';
  const quantos = mosaico.value.quadros.length;
  if (quantos === 2) return 'aspect-[3/4]';
  if (quantos === 3 && posicao === 0) return 'col-span-2 aspect-[2/1]';
  return 'aspect-square';
};

const anexo = item => item.attachments[0];
const ehVideo = item => anexo(item).fileType === ATTACHMENT_TYPES.VIDEO;
const temMais = posicao =>
  mosaico.value.escondidos > 0 && posicao === mosaico.value.quadros.length - 1;

const rotulo = (item, posicao) => {
  if (temMais(posicao)) {
    return t('CONVERSA_CANAL.ALBUM.MAIS', { n: mosaico.value.escondidos });
  }
  const valores = { n: posicao + 1, total: total.value };
  if (!item) return t('CONVERSA_CANAL.ALBUM.VAGA_SEM_TOTAL');
  return ehVideo(item)
    ? t('CONVERSA_CANAL.ALBUM.VIDEO', valores)
    : t('CONVERSA_CANAL.ALBUM.FOTO', valores);
};

const aberto = ref(null);
const galeriaAberta = computed({
  get: () => !!aberto.value,
  set: valor => {
    if (!valor) aberto.value = null;
  },
});
</script>

<template>
  <BaseBubble class="!p-[3px]" :data-bubble-name="nomeDoBalao">
    <div class="relative">
      <div
        class="grid grid-cols-2 gap-[3px] w-[330px] max-w-full rounded-[8px] overflow-hidden"
        role="group"
        :aria-label="rotuloDoGrupo"
        :aria-busy="chegada ? 'true' : undefined"
        data-album-do-whatsapp
        :data-album-chegando="chegada ? 'true' : undefined"
      >
        <template
          v-for="(item, posicao) in mosaico.quadros"
          :key="item ? item.id : `vaga-${posicao}`"
        >
          <div
            v-if="!item"
            role="img"
            class="grid place-content-center overflow-hidden bg-[#000]/10 dark:bg-white/10 animate-pulse"
            :class="formato(posicao)"
            :aria-label="rotulo(item, posicao)"
            data-quadro-reservado
          >
            <span
              class="i-ph-image size-8 text-[#000]/25 dark:text-white/25"
              aria-hidden="true"
            />
          </div>
          <button
            v-else
            :id="idDoQuadro(item, posicao)"
            type="button"
            class="relative block p-0 overflow-hidden bg-[#000]/10 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-[#25D366]"
            :class="[
              formato(posicao),
              destacado === item.id
                ? 'outline outline-[3px] -outline-offset-[3px] outline-[#25D366]'
                : '',
            ]"
            :aria-label="rotulo(item, posicao)"
            data-quadro-do-album
            @click="aberto = anexo(item)"
          >
            <video
              v-if="ehVideo(item)"
              class="block size-full object-cover skip-context-menu"
              preload="metadata"
              muted
              playsinline
              :src="`${anexo(item).dataUrl}#t=0.1`"
            />
            <img
              v-else
              class="block size-full object-cover skip-context-menu"
              alt=""
              :src="anexo(item).dataUrl"
            />
            <span
              v-if="ehVideo(item) && !temMais(posicao)"
              class="absolute inset-0 m-auto grid place-content-center size-11 rounded-full bg-[#000]/45 text-white pointer-events-none"
              aria-hidden="true"
            >
              <span class="i-ph-play-fill size-5 ms-0.5" />
            </span>
            <span
              v-if="temMais(posicao)"
              class="absolute inset-0 grid place-content-center bg-[#000]/50 text-white text-[26px] font-medium pointer-events-none"
              aria-hidden="true"
            >
              {{
                t('CONVERSA_CANAL.ALBUM.MAIS_CURTO', { n: mosaico.escondidos })
              }}
            </span>
          </button>
        </template>
      </div>
      <p
        v-if="chegada"
        class="absolute start-1.5 bottom-1.5 m-0 flex items-center gap-1 rounded-full bg-[#000]/55 px-2 py-0.5 text-[12px] leading-[16px] text-white pointer-events-none"
        role="status"
        data-recebendo-fotos
      >
        <span
          class="i-ph-circle-notch size-3.5 animate-spin"
          aria-hidden="true"
        />
        {{ t('CONVERSA_CANAL.ALBUM.RECEBENDO') }}
      </p>
    </div>
    <div
      v-if="legendas.length"
      class="w-[330px] max-w-full px-1.5 pt-1.5 text-[14.2px] leading-[19px]"
      data-legenda-do-album
    >
      <FormattedContent
        v-for="legenda in legendas"
        :key="legenda.id"
        :content="legenda.texto"
      />
    </div>
  </BaseBubble>
  <GalleryView
    v-if="aberto"
    v-model:show="galeriaAberta"
    :attachment="useSnakeCase(aberto)"
    :all-attachments="filteredCurrentChatAttachments"
    @close="aberto = null"
  />
</template>
