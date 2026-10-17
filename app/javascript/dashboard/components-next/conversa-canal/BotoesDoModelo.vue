<script setup>
// O que o cliente vê de uma mensagem de modelo além do texto (#1702), como no app:
//   parte "topo"     — dentro do balão, antes do texto: o topo do modelo (texto em
//                      negrito, foto, vídeo ou documento), o cartão do produto do
//                      catálogo e a oferta por tempo limitado;
//   parte "rodape"   — dentro do balão, logo depois do texto: o rodapé cinza;
//   parte "botoes"   — dentro do balão, depois da hora: um botão por linha, separados
//                      por um fio, na largura do balão. Com mais de 3, os 2 primeiros e
//                      "Ver todas as opções" (TodasAsOpcoesDoModelo);
//   parte "carrossel"— fora do balão, embaixo: os cartões lado a lado, com a mídia.
// Cada botão é um BotaoDoModelo: o de link abre o endereço que o cliente recebeu.
// Dentro do balão lê a mensagem do contexto; na lista recebe a mensagem por prop.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useMessageContext } from '../message/provider.js';
import { MESSAGE_STATUS } from '../message/constants';
import { useFuso, usePele } from './pele';
import { dataEHoraDaMensagem, idiomaDoPainel } from './dataDaConversa';
import { useModeloDaMensagem } from './useModeloDaMensagem';
import BotaoDoModelo from './BotaoDoModelo.vue';
import TodasAsOpcoesDoModelo from './TodasAsOpcoesDoModelo.vue';

const props = defineProps({
  parte: {
    type: String,
    required: true,
    validator: v => ['topo', 'rodape', 'botoes', 'carrossel'].includes(v),
  },
  message: { type: Object, default: null },
});

const { t, locale } = useI18n();
const pele = usePele();
const fuso = useFuso();
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
const { botoes, cartoes, oferta, produto, topo, rodape } =
  useModeloDaMensagem(mensagem);
// Mensagem que não saiu: o cliente não recebeu botão nenhum.
const falhou = computed(() => mensagem.value.status === MESSAGE_STATUS.FAILED);
// A parte que aparece: nenhuma sem a pele. A mensagem que não saiu fica sem botões e
// cartões, mas o topo e o rodapé são parte do que ela tentou dizer.
const parteVisivel = computed(() => {
  if (!pele.value) return null;
  if (falhou.value && ['botoes', 'carrossel'].includes(props.parte))
    return null;
  return props.parte;
});

// Até 3 botões, todos; mais que isso, os 2 primeiros e "Ver todas as opções" (app).
const MAX_NO_BALAO = 3;
const botoesNoBalao = computed(() =>
  botoes.value.length > MAX_NO_BALAO ? botoes.value.slice(0, 2) : botoes.value
);
const temMais = computed(() => botoes.value.length > MAX_NO_BALAO);

const NOME_DA_MIDIA = {
  image: 'CONVERSA_CANAL.MODELO.TOPO_FOTO',
  video: 'CONVERSA_CANAL.MODELO.TOPO_VIDEO',
  document: 'CONVERSA_CANAL.MODELO.TOPO_DOCUMENTO',
};
const ICONE_DA_MIDIA = {
  image: 'i-ph-image',
  video: 'i-ph-video',
  document: 'i-ph-file-text',
};
const midiaDoTopo = computed(() =>
  topo.value && topo.value.tipo !== 'text' ? topo.value : null
);

// "Termina em 20 de out. de 2026, 18:00", no fuso da conta; sem o fuso, nada (a hora
// nunca é lida no fuso do navegador).
const ofertaTermina = computed(() => {
  const expiraEm = oferta.value?.expiraEm;
  if (!expiraEm || !fuso.value) return '';
  return t('CONVERSA_CANAL.MODELO.OFERTA_TERMINA', {
    data: dataEHoraDaMensagem(
      expiraEm,
      fuso.value,
      idiomaDoPainel(locale.value)
    ),
  });
});

const LINHA =
  'flex items-center justify-center gap-1.5 min-h-11 -mx-[9px] w-[calc(100%+16px)] px-3 border-t border-[#0A0A0A]/10 dark:border-white/10 text-[#1A6B42] dark:text-[#6FD07E] text-[14.2px] font-medium';
const LINHA_DO_CARTAO =
  'flex items-center justify-center gap-1.5 min-h-11 border-t border-[#0A0A0A]/10 dark:border-white/10 text-[#1A6B42] dark:text-[#6FD07E] text-[14px] font-medium';
const SOMBRA = 'shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]';
const CAIXA = 'rounded-md bg-[#0A0A0A]/5 dark:bg-[#000]/20';
</script>

<template>
  <div
    v-if="parteVisivel === 'topo' && (topo || oferta || produto)"
    class="flex flex-col gap-1.5 mb-1.5"
    data-topo-do-modelo
  >
    <template v-if="midiaDoTopo">
      <img
        v-if="midiaDoTopo.tipo === 'image' && midiaDoTopo.url"
        :src="midiaDoTopo.url"
        :alt="t(NOME_DA_MIDIA.image)"
        class="w-full max-h-[330px] object-cover rounded-md skip-context-menu"
        data-topo-midia="image"
      />
      <video
        v-else-if="midiaDoTopo.tipo === 'video' && midiaDoTopo.url"
        :src="midiaDoTopo.url"
        :aria-label="t(NOME_DA_MIDIA.video)"
        controls
        preload="metadata"
        class="w-full max-h-[330px] rounded-md bg-[#000] skip-context-menu"
        data-topo-midia="video"
      />
      <component
        :is="midiaDoTopo.url ? 'a' : 'div'"
        v-else-if="midiaDoTopo.tipo === 'document'"
        :href="midiaDoTopo.url || undefined"
        :target="midiaDoTopo.url ? '_blank' : undefined"
        :rel="midiaDoTopo.url ? 'noopener noreferrer' : undefined"
        class="flex items-center gap-3 p-2 text-current"
        :class="CAIXA"
        data-topo-midia="document"
      >
        <Icon icon="i-ph-file-text" class="size-7 flex-shrink-0 opacity-70" />
        <span class="min-w-0 text-[14px] break-words">
          {{ midiaDoTopo.nome || t(NOME_DA_MIDIA.document) }}
        </span>
      </component>
      <div
        v-else
        class="grid place-content-center h-40 rounded-md bg-[#0A0A0A]/10 dark:bg-[#000]/20"
        role="img"
        :aria-label="t(NOME_DA_MIDIA[midiaDoTopo.tipo])"
        :data-topo-midia="midiaDoTopo.tipo"
      >
        <Icon
          :icon="ICONE_DA_MIDIA[midiaDoTopo.tipo]"
          class="size-10 opacity-60"
        />
      </div>
    </template>
    <div
      v-else-if="topo?.tipo === 'text'"
      class="text-[14.2px] leading-[19px] font-semibold break-words"
      data-topo-texto
    >
      {{ topo.texto }}
    </div>
    <div
      v-if="produto"
      class="flex items-center gap-3 p-2"
      :class="CAIXA"
      data-produto-do-modelo
    >
      <img
        v-if="produto.foto"
        :src="produto.foto"
        alt=""
        class="size-12 rounded object-cover flex-shrink-0 skip-context-menu"
      />
      <span
        v-else
        class="grid place-content-center size-12 rounded bg-[#0A0A0A]/10 dark:bg-white/10 flex-shrink-0"
      >
        <Icon icon="i-ph-storefront" class="size-6 opacity-70" />
      </span>
      <span class="flex flex-col min-w-0">
        <span class="text-[13px] font-medium break-words">
          {{ produto.nome || t('CONVERSA_CANAL.MODELO.PRODUTO') }}
        </span>
        <span
          v-if="produto.preco"
          class="text-[12px] text-[#666666] dark:text-[#A7A8A8]"
        >
          {{ produto.preco }}
        </span>
      </span>
    </div>
    <div
      v-if="oferta"
      class="flex items-start gap-2 p-2"
      :class="CAIXA"
      data-oferta-do-modelo
    >
      <Icon icon="i-ph-timer-bold" class="size-5 mt-0.5 text-[#E53935]" />
      <span class="flex flex-col">
        <span class="text-[14px] font-medium break-words">
          {{ oferta.texto || t('CONVERSA_CANAL.MODELO.OFERTA') }}
        </span>
        <span class="text-[12px] text-[#666666] dark:text-[#A7A8A8]">
          {{ ofertaTermina || t('CONVERSA_CANAL.MODELO.OFERTA') }}
        </span>
      </span>
    </div>
  </div>

  <div
    v-else-if="parteVisivel === 'rodape' && rodape"
    class="mt-1 text-[13px] leading-[17px] text-[#666666] dark:text-[#A7A8A8] break-words"
    data-rodape-do-modelo
  >
    {{ rodape }}
  </div>

  <div
    v-else-if="parteVisivel === 'botoes' && botoes.length"
    class="flex flex-col mt-1 -mb-[8px]"
    role="group"
    :aria-label="t('CONVERSA_CANAL.MODELO.BOTOES')"
    data-botoes-do-modelo
  >
    <BotaoDoModelo
      v-for="(botao, indice) in botoesNoBalao"
      :key="indice"
      :botao="botao"
      :classe="LINHA"
    />
    <TodasAsOpcoesDoModelo v-if="temMais" :botoes="botoes" :classe="LINHA" />
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
        <img
          v-if="cartao.midia.tipo === 'image' && cartao.midia.url"
          :src="cartao.midia.url"
          alt=""
          class="h-32 w-full object-cover rounded-[8px] skip-context-menu"
          data-midia-do-cartao="image"
        />
        <video
          v-else-if="cartao.midia.tipo === 'video' && cartao.midia.url"
          :src="cartao.midia.url"
          controls
          preload="metadata"
          class="h-32 w-full object-cover rounded-[8px] bg-[#000] skip-context-menu"
          data-midia-do-cartao="video"
        />
        <div
          v-else
          class="grid place-content-center h-32 rounded-[8px] bg-[#0A0A0A]/10 dark:bg-[#000]/20"
        >
          <Icon :icon="cartao.midia.icone" class="size-8 opacity-60" />
        </div>
        <p class="px-1.5 pt-1.5 pb-1 text-[14px] leading-[19px] break-words">
          {{ cartao.texto }}
        </p>
        <BotaoDoModelo
          v-for="(botao, i) in cartao.botoes"
          :key="i"
          :botao="botao"
          :classe="LINHA_DO_CARTAO"
        />
      </div>
    </div>
  </li>
  <!-- Sem a pele, ou com a mensagem que não saiu: não mostra nada. -->
  <template v-else />
</template>
