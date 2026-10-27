<script setup>
// #2211 — uma mensagem achada: de quem é a conversa, quando, quem mandou e o trecho com o achado
// destacado. Ao tocar, abre a conversa na mensagem (?messageId=; o MessagesView rola até ela).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { dataEHoraDaMensagem } from 'dashboard/components-next/conversa-canal/dataDaConversa';
import Avatar from 'next/avatar/Avatar.vue';
import { horaDaLista } from '../horaDaLista';
import { primeiroNome } from '../prefixoDoRemetente';
import { useRelogioDaLista } from '../useRelogioDaLista';
import { nomeNoAvatar, trechoComDestaque } from './buscaDaLista';

const props = defineProps({
  mensagem: { type: Object, required: true },
  busca: { type: String, required: true },
});

const ENTRADA = 0;
const QUEM = 'font-medium text-n-slate-12 me-1';
const MARCA = 'rounded-sm bg-n-amber-4 text-n-slate-12';

const { t } = useI18n();
const router = useRouter();
const agora = useRelogioDaLista();
const eu = useMapGetter('getCurrentUser');
const contaId = useMapGetter('getCurrentAccountId');
const contaPorId = useMapGetter('accounts/getAccount');
const fuso = computed(() => fusoDaConta(contaPorId.value?.(contaId.value)));

const peloAudio = computed(
  () =>
    Boolean(props.mensagem.transcribed_text) &&
    !trechoComDestaque(props.mensagem.content, props.busca).some(
      parte => parte.destaque
    )
);
const partes = computed(() =>
  trechoComDestaque(
    peloAudio.value ? props.mensagem.transcribed_text : props.mensagem.content,
    props.busca
  )
);

const quem = computed(() => {
  const { message_type: tipo, sender_type: tipoDoRemetente } = props.mensagem;
  if (props.mensagem.private) return t('LISTA_DE_CONVERSAS.BUSCA.NOTA');
  if (tipo === ENTRADA) return '';
  if (tipoDoRemetente === 'User' && props.mensagem.sender_id === eu.value?.id) {
    return t('LISTA_DE_CONVERSAS.BUSCA.VOCE');
  }
  return primeiroNome(props.mensagem.sender_name || '');
});

// "Áudio:" quando foi a transcrição que achou; senão, quem mandou ("Você:", "Ana:", "Nota:").
const rotuloDeQuem = computed(() => {
  const separador = t('LISTA_DE_CONVERSAS.PREFIXO.SEPARADOR');
  if (peloAudio.value)
    return `${t('LISTA_DE_CONVERSAS.BUSCA.AUDIO')}${separador}`;
  return quem.value ? `${quem.value}${separador}` : '';
});

const hora = computed(() =>
  horaDaLista({
    quando: props.mensagem.created_at,
    agora: agora.value,
    fuso: fuso.value,
    t,
  })
);

const rotulo = computed(() =>
  t('LISTA_DE_CONVERSAS.BUSCA.MENSAGEM_ARIA', {
    quem: quem.value || props.mensagem.contact_name || '',
    quando: dataEHoraDaMensagem(props.mensagem.created_at, fuso.value),
    contato: props.mensagem.contact_name || '',
  })
);

const abrir = () => {
  router.push({
    path: frontendURL(
      conversationUrl({
        accountId: contaId.value,
        id: props.mensagem.conversation_id,
      })
    ),
    query: { messageId: props.mensagem.id },
  });
};
</script>

<template>
  <button
    type="button"
    data-mensagem-achada
    class="flex w-full gap-3 px-4 py-3 text-start bg-transparent border-0 border-b border-n-weak hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand"
    :aria-label="rotulo"
    @click="abrir"
  >
    <Avatar
      :name="nomeNoAvatar(mensagem.contact_name)"
      :size="36"
      rounded-full
      class="flex-shrink-0"
    />
    <span class="flex flex-col flex-1 min-w-0 gap-0.5">
      <span class="flex items-center min-w-0 gap-2">
        <span class="flex-1 text-sm font-medium truncate text-n-slate-12">
          {{ mensagem.contact_name }}
        </span>
        <span class="flex-shrink-0 text-xs text-n-slate-11 tabular-nums">
          {{ hora }}
        </span>
      </span>
      <span class="text-sm leading-5 text-n-slate-11 line-clamp-2 break-words">
        <span
          v-if="peloAudio"
          class="i-lucide-mic size-3.5 align-[-2px] me-1 text-n-slate-12"
          aria-hidden="true"
        />
        <span v-if="rotuloDeQuem" :class="QUEM">{{ rotuloDeQuem }}</span>
        <template v-for="(parte, indice) in partes" :key="indice">
          <mark v-if="parte.destaque" :class="MARCA">{{ parte.texto }}</mark>
          <span v-else>{{ parte.texto }}</span>
        </template>
      </span>
    </span>
  </button>
</template>
