<script setup>
// Pedido do catálogo com a cara do WhatsApp (#1702): cartão com o ícone do carrinho,
// "Pedido", "N itens · total" e, embaixo de uma linha fina, "Ver pedido" em verde, que
// abre a lista de itens ali mesmo. O texto que o cliente escreveu junto vem embaixo.
// A hora fica acima da linha, como no contato (classesDaHora).
// O webhook só traz o código do produto (sem nome nem foto): a lista mostra o código.
// Pelo WAHA o pedido chega sem itens (#1709): fica o título que o cliente viu, "N itens"
// e o total, sem "Ver pedido" (não há o que abrir).
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from '../../message/bubbles/Base.vue';
import { useMessageContext } from '../../message/provider.js';
import { idiomaDoPainel } from '../dataDaConversa';
import { resumoDoPedido, valorEmDinheiro } from './pedido';

const { contentAttributes } = useMessageContext();
const { t, locale } = useI18n();

const pedido = computed(() => contentAttributes.value?.order || {});
const resumo = computed(() => resumoDoPedido(pedido.value));
const idioma = computed(() => idiomaDoPainel(locale.value));
const dinheiro = valor =>
  valorEmDinheiro(valor, resumo.value.moeda, idioma.value);

const quantos = computed(() =>
  t(
    'CONVERSA_CANAL.PEDIDO.ITENS',
    { n: resumo.value.unidades },
    resumo.value.unidades
  )
);
const linha = computed(() =>
  resumo.value.total === null
    ? quantos.value
    : `${quantos.value} · ${dinheiro(resumo.value.total)}`
);
const titulo = computed(() =>
  typeof pedido.value.title === 'string' && pedido.value.title.trim()
    ? pedido.value.title
    : t('CONVERSA_CANAL.PEDIDO.TITULO')
);
const temItens = computed(() => resumo.value.itens.length > 0);
const texto = computed(() =>
  typeof pedido.value.text === 'string' ? pedido.value.text : ''
);

const aberto = ref(false);
const idLista = `itens-${useId()}`;
</script>

<template>
  <BaseBubble class="!p-[3px]" data-bubble-name="pedido">
    <div class="w-[280px] max-w-full" data-pedido-do-whatsapp>
      <div
        class="flex items-center gap-3 p-2 rounded-[8px] bg-[#0A0A0A]/[0.04] dark:bg-white/[0.06]"
      >
        <span
          class="grid place-content-center size-12 shrink-0 rounded-[6px] bg-[#DFE5E7] dark:bg-[#3B4A54]"
          aria-hidden="true"
        >
          <span
            class="i-ph-shopping-cart-simple-fill size-6 text-[#54656F] dark:text-[#AEBAC1]"
          />
        </span>
        <span class="min-w-0">
          <span
            class="block text-[15px] font-medium break-words"
            data-titulo-do-pedido
          >
            {{ titulo }}
          </span>
          <span
            class="block text-[13px] text-[#666666] dark:text-[#A7A8A8]"
            data-resumo-do-pedido
          >
            {{ linha }}
          </span>
        </span>
      </div>
      <p
        v-if="texto"
        class="m-0 px-1.5 pt-1.5 text-[14.2px] leading-[19px] break-words whitespace-pre-wrap"
      >
        {{ texto }}
      </p>
      <ul
        v-if="aberto"
        :id="idLista"
        class="m-0 mt-1.5 px-1.5 flex flex-col gap-1 list-none text-[13px]"
        data-itens-do-pedido
      >
        <li
          v-for="(item, indice) in resumo.itens"
          :key="`${item.codigo}-${indice}`"
          class="flex justify-between gap-3"
        >
          <span class="min-w-0 truncate">
            {{
              t('CONVERSA_CANAL.PEDIDO.ITEM', {
                quantidade: item.quantidade,
                codigo: item.codigo,
              })
            }}
          </span>
          <span
            class="shrink-0 tabular-nums text-[#666666] dark:text-[#A7A8A8]"
          >
            {{ dinheiro(item.quantidade * item.preco) }}
          </span>
        </li>
      </ul>
      <button
        v-if="temItens"
        type="button"
        class="w-full h-11 mt-6 -mb-1 border-t border-[#000]/10 dark:border-white/10 text-[14px] font-medium text-[#1A6B42] dark:text-[#6FD07E] hover:bg-[#000]/[0.03] dark:hover:bg-white/[0.03] focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-[#25D366]"
        :aria-expanded="aberto"
        :aria-controls="idLista"
        data-ver-pedido
        @click="aberto = !aberto"
      >
        {{
          aberto
            ? t('CONVERSA_CANAL.PEDIDO.OCULTAR')
            : t('CONVERSA_CANAL.PEDIDO.VER')
        }}
      </button>
    </div>
  </BaseBubble>
</template>
