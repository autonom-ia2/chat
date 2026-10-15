<script setup>
// Os produtos do catálogo que vão na campanha (#1418), dentro de "O que esta
// mensagem precisa": o que já foi escolhido (foto, nome e preço, na ordem em
// que vão) e um botão só — Escolher ou Trocar —, que abre a gaveta.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import GavetaDeProdutos from './GavetaDeProdutos.vue';
import SeloBeta from '../components/SeloBeta.vue';

const props = defineProps({
  caixa: { type: [Number, String], required: true },
  // { tipo, minimo, maximo } (produtosNaCampanha.pedidoDeProdutos)
  pedido: { type: Object, required: true },
  escolhidos: { type: Array, default: () => [] },
});
const emit = defineEmits(['update']);

const { t } = useI18n();
const NS = 'MODELOS_WHATSAPP.PONTE.PRODUTOS';

const aberta = ref(false);
const temEscolha = computed(() => props.escolhidos.length > 0);
// Preço; no primeiro de vários, também que a foto dele vai na mensagem.
const PONTO = '·';
const detalhe = (produto, indice) => {
  const preco = produto.preco || '';
  return props.pedido.tipo === 'varios' && indice === 0
    ? [preco, PONTO, t(`${NS}.FOTO_DA_MENSAGEM`)].join(' ')
    : preco;
};

const usar = lista => {
  aberta.value = false;
  emit('update', lista);
};
const tirar = produto =>
  emit(
    'update',
    props.escolhidos.filter(item => item.id !== produto.id)
  );
// No carrossel, tirar abaixo do mínimo deixa a campanha pendente: a pessoa vê
// o aviso e escolhe outro.
const podeTirar = computed(() => props.pedido.tipo !== 'um');
</script>

<template>
  <div data-produtos-da-campanha class="flex flex-col gap-3">
    <div>
      <span class="text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.TITULO.${pedido.tipo}`) }}
      </span>
      <p class="m-0 mt-0.5 text-xs text-n-slate-11">
        {{ t(`${NS}.AJUDA.${pedido.tipo}`, { maximo: pedido.maximo }) }}
      </p>
    </div>
    <SeloBeta com-aviso />

    <ol
      v-if="temEscolha"
      class="flex flex-col gap-2 p-0 m-0 list-none"
      data-produtos-escolhidos
    >
      <li
        v-for="(produto, indice) in escolhidos"
        :key="produto.id"
        class="flex items-center gap-3 p-2 rounded-xl border bg-n-solid-1"
        :class="produto.disponivel ? 'border-n-weak' : 'border-n-ruby-7'"
      >
        <span
          v-if="pedido.tipo !== 'um'"
          class="w-5 text-sm font-semibold text-center text-n-slate-11 shrink-0"
        >
          {{ indice + 1 }}
        </span>
        <img
          v-if="produto.foto"
          :src="produto.foto"
          alt=""
          class="object-cover rounded-lg size-12 shrink-0 bg-n-slate-3"
        />
        <!-- Produto sem foto no catálogo: um quadro com o ícone, nunca a imagem quebrada. -->
        <span
          v-else
          class="grid rounded-lg place-items-center size-12 shrink-0 bg-n-slate-3 text-n-slate-10"
          aria-hidden="true"
        >
          <span class="i-lucide-shopping-bag size-5" />
        </span>
        <span class="flex flex-col flex-1 min-w-0">
          <span
            class="text-sm font-medium break-words line-clamp-2 text-n-slate-12"
          >
            {{ produto.nome }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ detalhe(produto, indice) }}
          </span>
          <span
            v-if="!produto.disponivel"
            role="alert"
            class="text-xs font-medium text-n-ruby-11"
          >
            {{ t(`${NS}.ACABOU`) }}
          </span>
        </span>
        <button
          v-if="podeTirar"
          type="button"
          :data-tirar-produto="produto.id"
          :aria-label="t(`${NS}.TIRAR`, { nome: produto.nome })"
          class="grid rounded-lg place-items-center size-11 shrink-0 text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="tirar(produto)"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
        </button>
      </li>
    </ol>

    <p
      v-if="temEscolha && escolhidos.length < pedido.minimo"
      role="alert"
      class="m-0 text-xs text-n-ruby-11"
    >
      {{
        t(
          `${NS}.FALTAM`,
          { n: pedido.minimo - escolhidos.length },
          pedido.minimo - escolhidos.length
        )
      }}
    </p>

    <Button
      :label="
        temEscolha
          ? t(`${NS}.TROCAR.${pedido.tipo}`)
          : t(`${NS}.ESCOLHER.${pedido.tipo}`)
      "
      :variant="temEscolha ? 'outline' : 'solid'"
      icon="i-lucide-shopping-bag"
      class="self-start"
      data-escolher-produtos
      @click="aberta = true"
    />

    <GavetaDeProdutos
      v-if="aberta"
      :caixa="caixa"
      :pedido="pedido"
      :escolhidos="escolhidos"
      @usar="usar"
      @fechar="aberta = false"
    />
  </div>
</template>
