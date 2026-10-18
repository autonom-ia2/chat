<script setup>
// Resposta do cliente a um formulário do WhatsApp (nfm_reply) na conversa com a cara
// do WhatsApp (#1702). No celular ela aparece como um balão "Resposta enviada" com o
// link "Ver resposta". Aqui o balão é o mesmo e, para a equipe, os campos já vêm
// abertos em "rótulo: valor" (o link fecha e abre a lista). Quando o cliente
// respondeu pelo formulário que mandamos, a citação no topo do balão (Base.vue) leva
// a ele, e o nome do formulário aparece embaixo do título.
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import BaseBubble from '../../message/bubbles/Base.vue';
import MessageMeta from '../../message/MessageMeta.vue';
import { useMessageContext } from '../../message/provider.js';
import { classesDaHora } from '../visualWhatsapp';
import { camposDaResposta, nomeDoFormulario } from './respostaDoFormulario';

const { t } = useI18n();
const { contentAttributes, inReplyTo, variant } = useMessageContext();
const idDaLista = useId();

const aberta = ref(true);
const campos = computed(() =>
  camposDaResposta(
    contentAttributes.value?.whatsappFlowResponse?.responseJson,
    {
      sim: t('CONVERSA_CANAL.FORMULARIO.SIM'),
      nao: t('CONVERSA_CANAL.FORMULARIO.NAO'),
    }
  )
);
const nome = computed(() => nomeDoFormulario(inReplyTo?.value));
const hora = computed(() =>
  classesDaHora({ variante: variant.value, nomeDoBalao: '' })
);
</script>

<template>
  <div class="w-[320px] max-w-full" data-resposta-do-formulario>
    <BaseBubble
      class="!px-[9px] !pt-[6px] !pb-0 text-[14.2px] leading-[19px]"
      data-bubble-name="whatsapp-flow-response"
      hide-meta
    >
      <div class="flex items-center gap-1.5 font-medium">
        <Icon icon="i-ph-note-pencil" class="size-[18px] flex-shrink-0" />
        {{ t('CONVERSA_CANAL.FORMULARIO.RESPOSTA_ENVIADA') }}
      </div>
      <div
        v-if="nome"
        class="text-xs text-[#666666] dark:text-[#A7A8A8] break-words"
      >
        {{ t('CONVERSA_CANAL.FORMULARIO.NOME', { nome }) }}
      </div>
      <p
        v-if="campos === null"
        class="mt-1 text-[13px] text-[#666666] dark:text-[#A7A8A8]"
        data-resposta-ilegivel
      >
        {{ t('CONVERSA_CANAL.FORMULARIO.ILEGIVEL') }}
      </p>
      <dl
        v-else-if="campos.length"
        v-show="aberta"
        :id="idDaLista"
        class="mt-1.5 flex flex-col gap-1.5"
      >
        <div v-for="campo in campos" :key="campo.chave" class="min-w-0">
          <dt class="text-xs text-[#666666] dark:text-[#A7A8A8] break-words">
            {{ campo.rotulo }}
          </dt>
          <dd class="whitespace-pre-wrap break-words">{{ campo.valor }}</dd>
        </div>
      </dl>
      <MessageMeta :class="hora" class="pb-1" />
      <button
        v-if="campos?.length"
        type="button"
        class="flex items-center justify-center gap-1.5 w-[calc(100%+18px)] -mx-[9px] min-h-11 px-3 border-t border-[#0A0A0A]/10 dark:border-white/10 text-[#1A6B42] dark:text-[#6FD07E] text-[14.2px] font-medium"
        :aria-expanded="aberta"
        :aria-controls="idDaLista"
        data-ver-resposta
        @click="aberta = !aberta"
      >
        {{
          aberta
            ? t('CONVERSA_CANAL.FORMULARIO.OCULTAR_RESPOSTA')
            : t('CONVERSA_CANAL.FORMULARIO.VER_RESPOSTA')
        }}
      </button>
    </BaseBubble>
  </div>
</template>
