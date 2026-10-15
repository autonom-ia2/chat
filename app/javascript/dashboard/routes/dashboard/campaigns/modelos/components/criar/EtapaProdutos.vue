<script setup>
// Produtos do catálogo (#1418): uma pergunta — como os produtos aparecem na
// mensagem (um, vários numa lista ou cartões lado a lado). Vários pede também o
// título. Os produtos em si a pessoa escolhe na hora de criar a campanha. Sem
// catálogo conectado: o aviso de sempre, com o caminho para conectar.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import EtapaCatalogo from './EtapaCatalogo.vue';
import SeloBeta from '../SeloBeta.vue';
import {
  JEITOS_DE_MOSTRAR_PRODUTOS,
  LIMITE_DO_TITULO_DOS_PRODUTOS,
} from '../../constants';
import { andarComSetas } from '../../helpers/setas';

const props = defineProps({
  catalogo: { type: Object, default: null },
});
const rascunho = defineModel('rascunho', { type: Object, required: true });

const { t } = useI18n();
const NS = 'MODELOS_WHATSAPP.PRODUTOS_NO_MODELO';
const BASE = 'MODELOS_WHATSAPP.FORMATOS.produtos';

const produtos = computed(() => rascunho.value.conteudo.produtos);

const atualizar = patch => {
  rascunho.value = {
    ...rascunho.value,
    conteudo: {
      ...rascunho.value.conteudo,
      produtos: { ...produtos.value, ...patch },
    },
  };
};

// O botão muda com o jeito: "Ver" num produto e nos cartões, "Ver itens" na lista.
const escolher = tipo =>
  atualizar({
    tipo,
    botao: { tipo: 'ver', texto: t(`${BASE}.BOTOES.${tipo}`) },
  });

const tituloErrado = computed(
  () => (produtos.value.titulo || '').length > LIMITE_DO_TITULO_DOS_PRODUTOS
);
</script>

<template>
  <div data-etapa-produtos class="flex flex-col gap-6">
    <SeloBeta com-aviso />
    <EtapaCatalogo v-if="!props.catalogo" :catalogo="null" />

    <fieldset class="flex flex-col gap-3 p-0 m-0 border-0">
      <legend class="mb-3 text-base font-semibold text-n-slate-12">
        {{ t(`${NS}.PERGUNTA`) }}
      </legend>
      <div
        role="radiogroup"
        :aria-label="t(`${NS}.PERGUNTA`)"
        class="grid gap-3 sm:grid-cols-3"
        @keydown="andarComSetas"
      >
        <button
          v-for="jeito in JEITOS_DE_MOSTRAR_PRODUTOS"
          :key="jeito"
          type="button"
          role="radio"
          :data-jeito="jeito"
          :aria-checked="produtos.tipo === jeito"
          :tabindex="produtos.tipo === jeito ? 0 : -1"
          class="flex flex-col gap-3 p-3 text-start rounded-2xl ring-1 ring-inset min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            produtos.tipo === jeito
              ? 'ring-2 ring-n-blue-8 bg-n-blue-2'
              : 'ring-n-weak bg-n-solid-1 hover:ring-n-blue-6'
          "
          @click="escolher(jeito)"
        >
          <!-- Desenho de como chega: sem texto de verdade. -->
          <span
            aria-hidden="true"
            class="flex items-end gap-1 p-2.5 rounded-xl h-20 bg-n-slate-3"
          >
            <span
              v-if="jeito === 'um'"
              class="flex flex-col w-3/5 overflow-hidden rounded bg-n-solid-1"
            >
              <span class="h-8 bg-n-teal-4" />
              <span class="h-1.5 m-1 w-2/3 rounded bg-n-slate-5" />
            </span>
            <span
              v-else-if="jeito === 'varios'"
              class="flex flex-col w-3/5 gap-1 p-1 rounded bg-n-solid-1"
            >
              <span class="flex items-center gap-1">
                <span class="rounded size-4 bg-n-teal-4" />
                <span class="w-8 h-1.5 rounded bg-n-slate-5" />
              </span>
              <span class="h-1.5 rounded bg-n-slate-5" />
              <span class="h-2.5 rounded bg-n-blue-4" />
            </span>
            <template v-else>
              <span
                v-for="n in 3"
                :key="n"
                class="flex flex-col w-1/3 overflow-hidden rounded bg-n-solid-1"
              >
                <span class="h-7 bg-n-teal-4" />
                <span class="h-1.5 m-1 rounded bg-n-slate-5" />
              </span>
            </template>
          </span>
          <span class="flex flex-col gap-0.5">
            <span class="text-sm font-semibold text-n-slate-12">
              {{ t(`${NS}.JEITOS.${jeito}.TITULO`) }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t(`${NS}.JEITOS.${jeito}.PARA`) }}
            </span>
          </span>
        </button>
      </div>
    </fieldset>

    <Input
      v-if="produtos.tipo === 'varios'"
      :model-value="produtos.titulo"
      :label="t(`${NS}.TITULO`)"
      :message="
        tituloErrado
          ? t(`${NS}.TITULO_ERRO`, { n: LIMITE_DO_TITULO_DOS_PRODUTOS })
          : t(`${NS}.TITULO_AJUDA`, { n: LIMITE_DO_TITULO_DOS_PRODUTOS })
      "
      :message-type="tituloErrado ? 'error' : 'info'"
      wrap-message
      custom-input-class="!h-11"
      data-titulo-produtos
      @update:model-value="titulo => atualizar({ titulo })"
    />

    <p
      class="flex gap-2 p-3 m-0 text-sm rounded-xl bg-n-blue-2 text-n-slate-12"
      data-produtos-na-campanha
    >
      <span
        class="i-lucide-shopping-cart size-4 mt-0.5 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      {{ t(`${NS}.ESCOLHE_NA_CAMPANHA`) }}
    </p>
  </div>
</template>
