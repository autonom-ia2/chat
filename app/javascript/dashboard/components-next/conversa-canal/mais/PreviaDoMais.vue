<script setup>
// Prévia, no fundo e no balão do WhatsApp, do que o cliente vai receber pelo "+" (#1702).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import BicoDoBalao from '../BicoDoBalao.vue';
import { FUNDO_DA_CONVERSA } from '../visualWhatsapp';
import { useHoraDaPele } from '../useHoraDaPele';
import {
  lerCoordenadas,
  montarBotaoDeLink,
  montarContato,
  montarEnquete,
  montarLocalizacao,
  montarOpcoes,
  montarPedidoDeLocalizacao,
  opcoesPreenchidas,
  textoParaQuemNaoTemFormato,
  viraLista,
} from './montarMensagem';

const props = defineProps({
  tipo: { type: String, required: true },
  campos: { type: Object, required: true },
  viraTexto: { type: Boolean, default: false },
});

// No WAHA o cliente recebe a versão em texto: a prévia mostra exatamente esse texto.
const MONTADORES = {
  botaoDeLink: montarBotaoDeLink,
  opcoes: montarOpcoes,
  localizacao: montarLocalizacao,
  pedidoDeLocalizacao: montarPedidoDeLocalizacao,
  contato: montarContato,
  enquete: montarEnquete,
};
const montado = computed(() =>
  props.viraTexto ? MONTADORES[props.tipo]?.({ ...props.campos }) || {} : {}
);
// A enquete que ainda não passa (montarEnquete recusa) não tem versão em texto: a
// prévia diz o que falta, em vez de mostrar um texto que não é o que vai sair.
const enqueteIncompleta = computed(
  () => props.viraTexto && props.tipo === 'enquete' && !montado.value.pedido
);
const emTexto = computed(() => {
  if (!props.viraTexto) return '';
  const { pedido } = montado.value;
  if (pedido) return textoParaQuemNaoTemFormato(pedido);
  return props.tipo === 'enquete' ? '' : props.campos.mensagem;
});

const { t } = useI18n();

const BALAO =
  'relative max-w-full rounded-lg ltr:rounded-tr-none rtl:rounded-tl-none bg-[#D9FDD3] dark:bg-[#144D37] text-[#0A0A0A] dark:text-[#FAFAFA] text-sm shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]';
const LINHA_DE_BOTAO =
  'flex items-center justify-center gap-1.5 min-h-10 px-3 border-t border-[#0A0A0A]/10 dark:border-white/10 text-[#1A6B42] dark:text-[#6FD07E] font-medium text-sm';

const opcoes = computed(() => opcoesPreenchidas(props.campos.opcoes || []));
const lista = computed(() => viraLista(props.campos.opcoes || []));
const temCoordenadas = computed(() =>
  Boolean(lerCoordenadas(props.campos.coordenadas))
);
// A hora de agora, no fuso da conta, como sairia a mensagem.
const agora = computed(() => Math.floor(Date.now() / 1000));
const hora = useHoraDaPele(agora);
const vazio = texto => !String(texto || '').trim();
</script>

<template>
  <div
    class="flex flex-col items-end gap-1 p-3 rounded-xl min-h-40"
    :class="FUNDO_DA_CONVERSA"
    data-previa-do-mais
  >
    <p
      v-if="viraTexto"
      class="self-stretch mb-1 px-2 py-1 rounded-md text-xs bg-white/80 dark:bg-[#000]/30 text-[#3B3B3B] dark:text-[#FAFAFA]"
    >
      {{
        tipo === 'enquete'
          ? t('CONVERSA_CANAL.PREVIA.ENQUETE_VIRA_TEXTO')
          : t('CONVERSA_CANAL.PREVIA.VIRA_TEXTO')
      }}
    </p>
    <div
      v-if="viraTexto"
      class="w-[15rem] max-w-full px-2.5 pt-1.5 pb-1"
      :class="BALAO"
    >
      <BicoDoBalao lado="right" class="text-[#D9FDD3] dark:text-[#144D37]" />
      <p
        v-if="enqueteIncompleta"
        class="italic text-[#666666] dark:text-[#A7A8A8] break-words"
        data-previa-vazia
      >
        {{ t('CONVERSA_CANAL.PREVIA.ENQUETE_INCOMPLETA') }}
      </p>
      <p v-else class="whitespace-pre-wrap break-words">
        {{ emTexto || t('CONVERSA_CANAL.PREVIA.SUA_MENSAGEM') }}
      </p>
      <div class="text-end text-[11px] text-[#666666] dark:text-[#FFFFFF]/60">
        {{ hora }}
      </div>
    </div>
    <div v-else class="w-[15rem] max-w-full" :class="BALAO">
      <BicoDoBalao lado="right" class="text-[#D9FDD3] dark:text-[#144D37]" />

      <template v-if="tipo === 'localizacao'">
        <div class="p-1">
          <div
            class="grid place-content-center h-28 rounded-md bg-[#E3E8DD] dark:bg-[#1F3A33] bg-[linear-gradient(90deg,rgba(255,255,255,0.5)_1px,transparent_1px),linear-gradient(rgba(255,255,255,0.5)_1px,transparent_1px)] bg-[length:22px_22px]"
          >
            <Icon
              icon="i-ph-map-pin-fill"
              class="size-8"
              :class="temCoordenadas ? 'text-[#E53935]' : 'text-[#A7A8A8]'"
            />
          </div>
          <div class="px-1.5 pt-1.5">
            <div class="font-medium break-words">
              {{ campos.nome || t('CONVERSA_CANAL.PREVIA.LUGAR') }}
            </div>
            <div
              v-if="campos.endereco"
              class="text-xs text-[#666666] dark:text-[#A7A8A8] break-words"
            >
              {{ campos.endereco }}
            </div>
          </div>
        </div>
      </template>

      <template v-else-if="tipo === 'enquete'">
        <div class="px-2.5 pt-1.5 pb-1" data-previa-enquete>
          <p
            class="font-semibold whitespace-pre-wrap break-words"
            :class="{
              'text-[#666666] dark:text-[#A7A8A8] italic font-normal': vazio(
                campos.pergunta
              ),
            }"
          >
            {{
              vazio(campos.pergunta)
                ? t('CONVERSA_CANAL.PREVIA.SUA_PERGUNTA')
                : campos.pergunta
            }}
          </p>
          <p class="text-xs text-[#666666] dark:text-[#A7A8A8]">
            {{
              campos.variasRespostas
                ? t('CONVERSA_CANAL.PREVIA.ENQUETE_VARIAS')
                : t('CONVERSA_CANAL.PREVIA.ENQUETE_UMA')
            }}
          </p>
          <ul class="flex flex-col gap-2 mt-2 m-0 list-none">
            <li
              v-for="(opcao, indice) in opcoes"
              :key="indice"
              class="flex items-center gap-2 break-words"
            >
              <span
                class="size-4 shrink-0 border-2 border-[#8C8C8C] dark:border-[#A7A8A8]"
                :class="campos.variasRespostas ? 'rounded-sm' : 'rounded-full'"
                aria-hidden="true"
              />
              <span class="min-w-0">{{ opcao }}</span>
            </li>
          </ul>
          <div
            class="text-end text-[11px] text-[#666666] dark:text-[#FFFFFF]/60"
          >
            {{ hora }}
          </div>
        </div>
      </template>

      <template v-else-if="tipo === 'contato'">
        <div class="flex items-center gap-3 px-3 py-3">
          <span
            class="grid place-content-center size-10 rounded-full bg-[#DFE5E7] dark:bg-[#6A7175] text-white"
          >
            <Icon icon="i-ph-user-fill" class="size-6" />
          </span>
          <span class="font-medium break-words min-w-0">
            {{ campos.nome || t('CONVERSA_CANAL.PREVIA.CONTATO') }}
          </span>
        </div>
      </template>

      <template v-else>
        <p
          v-if="tipo === 'opcoes' && !viraTexto && !vazio(campos.cabecalho)"
          class="px-2.5 pt-1.5 font-semibold break-words"
        >
          {{ campos.cabecalho }}
        </p>
        <p
          class="px-2.5 pt-1.5 pb-1 whitespace-pre-wrap break-words"
          :class="{
            'text-[#666666] dark:text-[#A7A8A8] italic': vazio(campos.mensagem),
          }"
        >
          {{
            vazio(campos.mensagem)
              ? t('CONVERSA_CANAL.PREVIA.SUA_MENSAGEM')
              : campos.mensagem
          }}
        </p>
        <div
          class="px-2.5 pb-1 text-end text-[11px] text-[#666666] dark:text-[#FFFFFF]/60"
        >
          {{ hora }}
        </div>
        <div v-if="tipo === 'botaoDeLink'" :class="LINHA_DE_BOTAO">
          <Icon icon="i-ph-arrow-square-out" class="size-4" />
          {{ campos.nomeDoBotao || t('CONVERSA_CANAL.PREVIA.BOTAO') }}
        </div>
        <div v-else-if="tipo === 'pedidoDeLocalizacao'" :class="LINHA_DE_BOTAO">
          <Icon icon="i-ph-map-pin" class="size-4" />
          {{ t('CONVERSA_CANAL.PREVIA.ENVIAR_LOCALIZACAO') }}
        </div>
        <div v-else-if="tipo === 'formulario'" :class="LINHA_DE_BOTAO">
          <Icon icon="i-ph-note-pencil" class="size-4" />
          {{ campos.textoDoBotao || t('CONVERSA_CANAL.PREVIA.BOTAO') }}
        </div>
        <div v-else-if="tipo === 'opcoes' && lista" :class="LINHA_DE_BOTAO">
          <Icon icon="i-ph-list-bullets" class="size-4" />
          {{ campos.nomeDaLista || t('CONVERSA_CANAL.PREVIA.LISTA') }}
        </div>
      </template>
    </div>

    <template v-if="tipo === 'opcoes' && !lista && !viraTexto">
      <div
        v-for="(opcao, indice) in opcoes"
        :key="indice"
        class="w-[15rem] max-w-full grid place-content-center min-h-10 px-3 rounded-lg bg-white dark:bg-[#242626] text-[#1A6B42] dark:text-[#6FD07E] text-sm font-medium shadow-[0_1px_0.5px_rgba(11,20,26,0.13)] break-words text-center"
      >
        {{ opcao }}
      </div>
    </template>
  </div>
</template>
