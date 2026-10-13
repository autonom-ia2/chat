<script setup>
// No passo Mensagem da Nova campanha (#1334), o que o formato do modelo
// escolhido pede antes do envio: o código do cupom, até quando vale a oferta e
// a foto ou o vídeo de cada cartão do carrossel (o aprovado com o modelo, ou um
// arquivo escolhido agora, que sobe na hora). Catálogo e formulário só avisam o
// que acontece. Uma pergunta por bloco.
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import EscolherArquivo from '../components/criar/EscolherArquivo.vue';
import api from '../api/modelosWhatsapp';
import { arquivoGuardado } from '../api/arquivos';
import {
  ACEITA_NO_CARTAO,
  CODIGO_MAXIMO,
  oQuePedir,
  pendencias,
} from '../helpers/formatoNaCampanha';
import {
  scheduleToUtc,
  timeZoneName,
} from 'dashboard/components-next/CampaignJourney/scheduleTime';

const props = defineProps({
  modelo: { type: Object, required: true },
  valores: { type: Object, default: () => ({}) },
  caixa: { type: [Number, String], default: null },
  timeZone: { type: String, default: 'UTC' },
});
const emit = defineEmits(['update']);

const { t, locale } = useI18n();
const NS = 'MODELOS_WHATSAPP.PONTE.FORMATO';

// O fuso pelo nome que a pessoa conhece ("Horário Padrão de Brasília"), o mesmo
// da revisão (#1387), lido na data escolhida (horário de verão).
const nomeDoFuso = computed(() =>
  timeZoneName(
    props.timeZone,
    locale.value,
    scheduleToUtc(props.valores.validade, props.timeZone) || undefined
  )
);

const pedido = computed(() =>
  oQuePedir(props.modelo.template, props.modelo.cartoesGuardados || [])
);
// Cupom vazio é o começo: o código de exemplo do modelo aparece só como dica,
// para nunca ir sem querer para o público inteiro.
const mensagemDoCupom = computed(() => {
  const codigo = (props.valores.cupom || '').trim();
  if (!codigo) return t(`${NS}.CUPOM_VAZIO`);
  if (codigo.length > CODIGO_MAXIMO) {
    return t(`${NS}.CUPOM_ERRO`, { n: CODIGO_MAXIMO });
  }
  return t(`${NS}.CUPOM_AJUDA`, { n: CODIGO_MAXIMO });
});

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

// Trocou de modelo enquanto o arquivo subia: o resultado é do modelo anterior e
// não entra no rascunho do novo.
let ativo = true;
onBeforeUnmount(() => {
  ativo = false;
});

const atualizar = patch => {
  if (ativo) emit('update', { ...props.valores, ...patch });
};
const comCartao = (indice, arquivo) => {
  const cartoes = { ...(props.valores.cartoes || {}) };
  if (arquivo) cartoes[indice] = arquivo;
  else delete cartoes[indice];
  atualizar({ cartoes });
};

// O arquivo sobe assim que é escolhido; enquanto sobe, o cartão diz "Enviando".
const enviando = ref({});
const erroDoEnvio = ref({});
const escolher = async (indice, { arquivo, local }) => {
  enviando.value = { ...enviando.value, [indice]: arquivo };
  erroDoEnvio.value = { ...erroDoEnvio.value, [indice]: '' };
  try {
    comCartao(
      indice,
      await api.subirArquivoDaCampanha(props.caixa, arquivoGuardado(local))
    );
  } catch (erro) {
    erroDoEnvio.value = {
      ...erroDoEnvio.value,
      [indice]: erro?.mensagem || t(`${NS}.CARTAO_ERRO`),
    };
  } finally {
    enviando.value = { ...enviando.value, [indice]: '' };
  }
};

const descricao = cartao => {
  const novo = props.valores.cartoes?.[cartao.indice];
  if (enviando.value[cartao.indice]) {
    return t(`${NS}.CARTAO_ENVIANDO`, {
      arquivo: enviando.value[cartao.indice],
    });
  }
  if (novo) return t(`${NS}.CARTAO_ESCOLHIDO`, { arquivo: novo.nome });
  if (cartao.guardado) {
    return t(`${NS}.CARTAO_GUARDADO`, { arquivo: cartao.guardado.nome });
  }
  return t(`${NS}.CARTAO_SEM_ARQUIVO_${cartao.midia.toUpperCase()}`);
};
</script>

<template>
  <!-- Raiz fixa (vue/no-root-v-if): sem nada a preencher, o bloco some. -->
  <div class="contents">
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
        :placeholder="
          pedido.cupom.exemplo
            ? t(`${NS}.CUPOM_EXEMPLO`, { exemplo: pedido.cupom.exemplo })
            : ''
        "
        :message="mensagemDoCupom"
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
        :label="t(`${NS}.VALIDADE`, { zona: nomeDoFuso })"
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
            class="flex flex-wrap gap-3 items-center p-3 rounded-xl border border-n-weak bg-n-solid-1"
            :data-formato-cartao="cartao.indice"
          >
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
            <span class="flex flex-col flex-1 min-w-0 basis-48">
              <strong class="text-sm text-n-slate-12">
                {{ t(`${NS}.CARTAO`, { n: cartao.indice + 1 }) }}
              </strong>
              <span
                class="text-xs break-words text-n-slate-11"
                aria-live="polite"
              >
                {{ descricao(cartao) }}
              </span>
              <span
                v-if="erroDoEnvio[cartao.indice]"
                role="alert"
                class="text-xs text-n-ruby-11"
              >
                {{ erroDoEnvio[cartao.indice] }}
              </span>
            </span>
            <span class="flex flex-wrap gap-2 items-center w-full sm:w-auto">
              <EscolherArquivo
                :aceita="ACEITA_NO_CARTAO[cartao.midia]"
                :rotulo="
                  cartao.guardado || valores.cartoes?.[cartao.indice]
                    ? t(`${NS}.CARTAO_TROCAR_${cartao.midia.toUpperCase()}`)
                    : t(`${NS}.CARTAO_ESCOLHER_${cartao.midia.toUpperCase()}`)
                "
                @escolhido="arquivo => escolher(cartao.indice, arquivo)"
              />
              <button
                v-if="cartao.guardado && valores.cartoes?.[cartao.indice]"
                type="button"
                class="px-2 text-sm min-h-11 text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand rounded-lg"
                @click="comCartao(cartao.indice, null)"
              >
                {{ t(`${NS}.CARTAO_VOLTAR`) }}
              </button>
            </span>
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
  </div>
</template>
