<script setup>
// "Como o cliente vê" o modelo de produto ou de carrossel (#1716), no fundo e
// no balão do WhatsApp da conversa (#1702), com o que o atendente já escolheu:
//   um        — o produto no topo do balão (foto, nome, preço);
//   varios    — a foto do primeiro, o título, quantos itens e a lista do "Ver itens";
//   carrossel — um cartão por produto, na ordem escolhida;
//   cartoes   — os cartões com a foto e os espaços preenchidos (o da vez marcado).
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import BicoDoBalao from 'dashboard/components-next/conversa-canal/BicoDoBalao.vue';
import { FUNDO_DA_CONVERSA } from 'dashboard/components-next/conversa-canal/visualWhatsapp';
import { useHoraDaPele } from 'dashboard/components-next/conversa-canal/useHoraDaPele';
import PrecoDoProduto from './PrecoDoProduto.vue';
import { cartoesDoModelo, comEspacos, componenteDe } from './modeloNaConversa';

const props = defineProps({
  template: { type: Object, required: true },
  tipo: { type: String, required: true },
  corpo: { type: Object, default: () => ({}) },
  produtos: { type: Array, default: () => [] },
  // { [indice]: { imagem, campos } }
  cartoes: { type: Object, default: () => ({}) },
  cartaoAtual: { type: Number, default: -1 },
});

const { t } = useI18n();
const NS = 'MODELOS_WHATSAPP.CONVERSA.PREVIA';

const BALAO =
  'relative max-w-full rounded-lg ltr:rounded-tr-none rtl:rounded-tl-none bg-[#D9FDD3] dark:bg-[#005C4B] text-[#111B21] dark:text-[#E9EDEF] text-sm shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]';
const CARTAO =
  'flex flex-col shrink-0 w-44 p-[3px] snap-start rounded-lg bg-[#D9FDD3] dark:bg-[#005C4B] text-[#111B21] dark:text-[#E9EDEF] shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]';
const LINHA_DE_BOTAO =
  'flex items-center justify-center gap-1.5 min-h-10 px-3 border-t border-[#111B21]/10 dark:border-white/10 text-[#027EB5] dark:text-[#53BDEB] font-medium text-sm';
const CINZA = 'text-[#667781] dark:text-[#8696A0]';

const agora = computed(() => Math.floor(Date.now() / 1000));
const hora = useHoraDaPele(agora);

const espaco = n => t('MODELOS_WHATSAPP.CONVERSA.CARTAO.ESPACO', { n });
const texto = computed(() =>
  comEspacos(componenteDe(props.template, 'BODY')?.text, props.corpo, espaco)
);
const rodape = computed(() => componenteDe(props.template, 'FOOTER')?.text);
const titulo = computed(() => {
  const topo = componenteDe(props.template, 'HEADER');
  return topo?.format === 'TEXT' ? topo.text : '';
});
const botao = computed(
  () => componenteDe(props.template, 'BUTTONS')?.buttons?.[0]?.text || ''
);
const primeiro = computed(() => props.produtos[0] || null);
const modeloDosCartoes = computed(() => cartoesDoModelo(props.template));
const botaoDoCartao = computed(
  () => modeloDosCartoes.value[0]?.botoes?.[0]?.texto || ''
);
const valorDoCartao = indice => props.cartoes[indice] || {};

// O cartão da vez aparece na prévia (a fila de cartões rola até ele).
const fila = ref(null);
watch(
  () => props.cartaoAtual,
  async indice => {
    await nextTick();
    if (!fila.value) return;
    const alvo = fila.value.querySelector(`[data-previa-cartao="${indice}"]`);
    fila.value.scrollLeft = alvo ? Math.max(alvo.offsetLeft - 8, 0) : 0;
  },
  { immediate: true }
);
</script>

<template>
  <div
    class="flex flex-col items-end gap-1 p-3 overflow-hidden rounded-xl min-h-40"
    :class="FUNDO_DA_CONVERSA"
    data-previa-do-modelo
  >
    <div class="w-[15.5rem] max-w-full" :class="BALAO">
      <BicoDoBalao lado="right" class="text-[#D9FDD3] dark:text-[#005C4B]" />

      <div v-if="tipo === 'um'" class="p-1" data-previa-produto>
        <div
          class="grid overflow-hidden rounded-md h-36 place-content-center bg-[#111B21]/10 dark:bg-black/20"
        >
          <img
            v-if="primeiro?.foto"
            :src="primeiro.foto"
            alt=""
            class="object-cover w-60 h-36"
          />
          <Icon v-else icon="i-ph-storefront" class="size-9 opacity-60" />
        </div>
        <div class="px-1.5 pt-1.5">
          <div class="font-medium break-words">
            {{ primeiro?.nome || t(`${NS}.PRODUTO`) }}
          </div>
          <PrecoDoProduto
            v-if="primeiro"
            :produto="primeiro"
            class="text-xs"
            :class="CINZA"
          />
        </div>
      </div>

      <div
        v-else-if="tipo === 'varios'"
        class="flex items-center gap-2.5 m-1 p-1.5 rounded-md bg-[#111B21]/5 dark:bg-black/20"
        data-previa-varios
      >
        <span
          class="grid overflow-hidden rounded size-12 shrink-0 place-content-center bg-[#111B21]/10 dark:bg-white/10"
        >
          <img
            v-if="primeiro?.foto"
            :src="primeiro.foto"
            alt=""
            class="object-cover size-12"
          />
          <Icon v-else icon="i-ph-storefront" class="size-6 opacity-60" />
        </span>
        <span class="flex flex-col min-w-0">
          <strong class="text-sm leading-snug break-words">
            {{ titulo || t(`${NS}.PRODUTOS`) }}
          </strong>
          <span class="text-xs" :class="CINZA">
            {{ t(`${NS}.ITENS`, { n: produtos.length }, produtos.length) }}
          </span>
        </span>
      </div>

      <p class="px-2.5 pt-1.5 pb-1 mb-0 whitespace-pre-wrap break-words">
        {{ texto }}
      </p>
      <p v-if="rodape" class="px-2.5 mb-0 text-xs" :class="CINZA">
        {{ rodape }}
      </p>
      <div class="px-2.5 pb-1 text-end text-[0.6875rem]" :class="CINZA">
        {{ hora }}
      </div>
      <div
        v-if="(tipo === 'um' || tipo === 'varios') && botao"
        :class="LINHA_DE_BOTAO"
      >
        <Icon
          :icon="tipo === 'varios' ? 'i-ph-list-bullets' : 'i-ph-storefront'"
          class="size-4"
        />
        {{ botao }}
      </div>
    </div>

    <div
      v-if="tipo === 'varios' && produtos.length"
      class="w-[15.5rem] max-w-full flex flex-col gap-1 p-2 rounded-lg bg-white/90 dark:bg-[#202C33]"
      data-previa-ver-itens
    >
      <span class="px-1 text-[0.6875rem]" :class="CINZA">
        {{ t(`${NS}.AO_TOCAR`, { botao }) }}
      </span>
      <span
        v-for="(produto, indice) in produtos"
        :key="produto.id"
        class="flex items-center gap-2 p-1 rounded-md"
      >
        <span class="w-4 text-[0.6875rem] text-center" :class="CINZA">
          {{ indice + 1 }}
        </span>
        <span
          class="grid overflow-hidden rounded size-9 shrink-0 place-content-center bg-[#111B21]/10 dark:bg-white/10"
        >
          <img
            v-if="produto.foto"
            :src="produto.foto"
            alt=""
            class="object-cover size-9"
          />
          <Icon v-else icon="i-ph-storefront" class="size-5 opacity-60" />
        </span>
        <span class="flex flex-col min-w-0">
          <span
            class="text-xs font-medium truncate text-[#111B21] dark:text-[#E9EDEF]"
          >
            {{ produto.nome }}
          </span>
          <PrecoDoProduto
            :produto="produto"
            class="text-[0.6875rem]"
            :class="CINZA"
          />
        </span>
      </span>
    </div>

    <ul
      v-if="tipo === 'carrossel' || tipo === 'cartoes'"
      ref="fila"
      class="relative flex self-stretch gap-2 p-0 pb-1 m-0 overflow-x-auto list-none snap-x"
      :aria-label="t(`${NS}.CARTOES`)"
      data-previa-cartoes
    >
      <template v-if="tipo === 'carrossel'">
        <li
          v-for="(produto, indice) in produtos"
          :key="produto.id"
          :class="CARTAO"
          :data-previa-cartao="indice"
        >
          <span
            class="grid h-24 overflow-hidden rounded-md place-content-center bg-[#111B21]/10 dark:bg-black/20"
          >
            <img
              v-if="produto.foto"
              :src="produto.foto"
              alt=""
              class="object-cover w-[10.6rem] h-24"
            />
            <Icon v-else icon="i-ph-storefront" class="size-7 opacity-60" />
          </span>
          <span class="px-1.5 pt-1.5 pb-1 text-xs leading-snug break-words">
            <strong class="block font-medium">{{ produto.nome }}</strong>
            <PrecoDoProduto :produto="produto" :class="CINZA" />
          </span>
          <span
            v-if="botaoDoCartao"
            class="flex items-center justify-center gap-1 mt-auto min-h-9 text-xs font-medium border-t border-[#111B21]/10 dark:border-white/10 text-[#027EB5] dark:text-[#53BDEB]"
          >
            <Icon icon="i-ph-storefront" class="size-3.5" />
            {{ botaoDoCartao }}
          </span>
        </li>
      </template>
      <template v-else>
        <li
          v-for="cartao in modeloDosCartoes"
          :key="cartao.indice"
          :class="[
            CARTAO,
            cartao.indice === cartaoAtual
              ? 'ring-2 ring-offset-2 ring-[#25D366] ring-offset-transparent'
              : '',
          ]"
          :data-previa-cartao="cartao.indice"
        >
          <span
            class="grid h-24 overflow-hidden rounded-md place-content-center bg-[#111B21]/10 dark:bg-black/20"
          >
            <img
              v-if="valorDoCartao(cartao.indice).imagem"
              :src="valorDoCartao(cartao.indice).imagem"
              alt=""
              class="object-cover w-[10.6rem] h-24"
            />
            <Icon v-else icon="i-ph-image" class="size-7 opacity-60" />
          </span>
          <p class="px-1.5 pt-1.5 pb-1 mb-0 text-xs leading-snug break-words">
            {{
              comEspacos(
                cartao.corpo?.text,
                valorDoCartao(cartao.indice).campos,
                espaco
              )
            }}
          </p>
          <span
            v-for="(item, posicao) in cartao.botoes"
            :key="posicao"
            class="flex items-center justify-center gap-1 mt-auto min-h-9 text-xs font-medium border-t border-[#111B21]/10 dark:border-white/10 text-[#027EB5] dark:text-[#53BDEB]"
          >
            <Icon
              :icon="
                item.tipo === 'URL'
                  ? 'i-ph-arrow-square-out'
                  : 'i-ph-arrow-bend-up-left'
              "
              class="size-3.5"
            />
            {{ item.texto }}
          </span>
        </li>
      </template>
    </ul>
  </div>
</template>
