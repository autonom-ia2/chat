<script setup>
// PROTÓTIPO #1334 (aguarda aprovação do Rodrigo): no passo Mensagem da Nova
// campanha, o que o formato do modelo escolhido pede antes do envio — cupom,
// até quando vale a oferta, a foto de cada cartão do carrossel — e o aviso do
// que acontece nos botões de catálogo e formulário. Uma pergunta por bloco.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { CODIGO_MAXIMO, oQuePedir, pendencias } from './formatoNaCampanha';

const props = defineProps({
  modelo: { type: Object, required: true },
  valores: { type: Object, default: () => ({}) },
  guardados: { type: Array, default: () => [] },
  timeZone: { type: String, default: 'UTC' },
});
const emit = defineEmits(['update']);

const { t } = useI18n();
const NS = 'MODELOS_WHATSAPP.PONTE.FORMATO';

const pedido = computed(() =>
  oQuePedir(props.modelo.template, props.guardados)
);
const faltando = computed(() =>
  pendencias(pedido.value, props.valores, { timeZone: props.timeZone })
);
const temAlgo = computed(
  () =>
    pedido.value.cupom ||
    pedido.value.validade ||
    pedido.value.cartoes.length ||
    pedido.value.catalogo ||
    pedido.value.formulario
);

// Cartão com arquivo guardado: o link só aparece se a pessoa pedir.
const trocando = ref({});
const mostrarLink = cartao => !cartao.guardado || trocando.value[cartao.indice];

const atualizar = patch => emit('update', { ...props.valores, ...patch });
const linkDoCartao = (indice, link) =>
  atualizar({ cartoes: { ...(props.valores.cartoes || {}), [indice]: link } });
const usarGuardado = indice => {
  trocando.value = { ...trocando.value, [indice]: false };
  linkDoCartao(indice, '');
};
</script>

<template>
  <section
    v-if="temAlgo"
    data-ponte-formato
    class="flex flex-col gap-4 p-4 rounded-xl border border-n-weak bg-n-alpha-1"
  >
    <div>
      <h3 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.TITULO`) }}
      </h3>
      <p class="m-0 mt-1 text-xs text-n-slate-11">
        {{ t(`${NS}.AJUDA`) }}
      </p>
    </div>

    <Input
      v-if="pedido.cupom"
      :model-value="valores.cupom || ''"
      :label="t(`${NS}.CUPOM`)"
      :message="
        faltando.includes('CUPOM')
          ? t(`${NS}.CUPOM_ERRO`, { n: CODIGO_MAXIMO })
          : t(`${NS}.CUPOM_AJUDA`, { n: CODIGO_MAXIMO })
      "
      :message-type="faltando.includes('CUPOM') ? 'error' : 'info'"
      wrap-message
      custom-input-class="!h-11"
      data-formato-cupom
      @update:model-value="cupom => atualizar({ cupom })"
    />

    <Input
      v-if="pedido.validade"
      :model-value="valores.validade || ''"
      type="datetime-local"
      :label="t(`${NS}.VALIDADE`, { zona: timeZone })"
      :message="
        faltando.includes('VALIDADE_PASSADA')
          ? t(`${NS}.VALIDADE_PASSADA`)
          : t(`${NS}.VALIDADE_AJUDA`)
      "
      :message-type="faltando.includes('VALIDADE_PASSADA') ? 'error' : 'info'"
      wrap-message
      custom-input-class="!h-11"
      data-formato-validade
      @update:model-value="validade => atualizar({ validade })"
    />

    <div v-if="pedido.cartoes.length" class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.CARTOES`, { n: pedido.cartoes.length }) }}
      </span>
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="cartao in pedido.cartoes"
          :key="cartao.indice"
          class="flex flex-col gap-2 p-3 rounded-xl border border-n-weak bg-n-solid-1"
          :data-formato-cartao="cartao.indice"
        >
          <div class="flex flex-wrap gap-3 items-center">
            <span
              class="flex justify-center items-center rounded-lg size-11 shrink-0 bg-n-blue-3 text-n-blue-11"
              aria-hidden="true"
            >
              <span
                :class="
                  cartao.midia === 'video' ? 'i-lucide-video' : 'i-lucide-image'
                "
                class="size-5"
              />
            </span>
            <span class="flex flex-col flex-1 min-w-0">
              <strong class="text-sm text-n-slate-12">
                {{ t(`${NS}.CARTAO`, { n: cartao.indice + 1 }) }}
              </strong>
              <span class="text-xs truncate text-n-slate-11">
                {{
                  cartao.guardado && !mostrarLink(cartao)
                    ? t(`${NS}.CARTAO_GUARDADO`, {
                        arquivo: cartao.guardado.nome,
                      })
                    : t(
                        `${NS}.CARTAO_SEM_ARQUIVO_${cartao.midia.toUpperCase()}`
                      )
                }}
              </span>
            </span>
            <Button
              v-if="cartao.guardado && !mostrarLink(cartao)"
              :label="t(`${NS}.CARTAO_TROCAR`)"
              variant="ghost"
              size="sm"
              class="!min-h-11"
              @click="trocando = { ...trocando, [cartao.indice]: true }"
            />
            <Button
              v-else-if="cartao.guardado"
              :label="t(`${NS}.CARTAO_VOLTAR`)"
              variant="ghost"
              size="sm"
              class="!min-h-11"
              @click="usarGuardado(cartao.indice)"
            />
          </div>
          <Input
            v-if="mostrarLink(cartao)"
            :model-value="valores.cartoes?.[cartao.indice] || ''"
            type="url"
            :label="t(`${NS}.CARTAO_LINK`)"
            :placeholder="t(`${NS}.CARTAO_LINK_EXEMPLO`)"
            custom-input-class="!h-11"
            @update:model-value="link => linkDoCartao(cartao.indice, link)"
          />
        </li>
      </ul>
    </div>

    <p
      v-if="pedido.catalogo"
      class="flex gap-2 p-3 m-0 text-sm rounded-xl bg-n-blue-2 text-n-slate-12"
      data-formato-catalogo
    >
      <span
        class="i-lucide-shopping-bag size-4 mt-0.5 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      {{ t(`${NS}.CATALOGO`) }}
    </p>
    <p
      v-if="pedido.formulario"
      class="flex gap-2 p-3 m-0 text-sm rounded-xl bg-n-blue-2 text-n-slate-12"
      data-formato-formulario
    >
      <span
        class="i-lucide-clipboard-list size-4 mt-0.5 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      {{ t(`${NS}.FORMULARIO`, { botao: pedido.formulario.text || '' }) }}
    </p>
  </section>
</template>
