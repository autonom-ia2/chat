<script setup>
// No passo Mensagem da Nova campanha (#1334), o que o formato do modelo
// escolhido pede antes do envio: a foto, o vídeo ou o documento do topo (#1465),
// o código do cupom, até quando vale a oferta e a foto ou o vídeo de cada cartão
// do carrossel. Cada arquivo é o aprovado com o modelo, ou um escolhido agora,
// que sobe na hora. Catálogo e formulário só avisam o que acontece. Uma
// pergunta por bloco.
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import { accountZoneLabel } from 'dashboard/components-next/CampaignJourney/scheduleTime';
import ArquivoDaCampanha from './ArquivoDaCampanha.vue';
import api from '../api/modelosWhatsapp';
import { arquivoGuardado } from '../api/arquivos';
import {
  CODIGO_MAXIMO,
  oQuePedir,
  pendencias,
} from '../helpers/formatoNaCampanha';

const props = defineProps({
  modelo: { type: Object, required: true },
  valores: { type: Object, default: () => ({}) },
  caixa: { type: [Number, String], default: null },
  timeZone: { type: String, default: 'UTC' },
});
const emit = defineEmits(['update']);

const { t } = useI18n();
const NS = 'MODELOS_WHATSAPP.PONTE.FORMATO';

const pedido = computed(() =>
  oQuePedir(
    props.modelo.template,
    props.modelo.cartoesGuardados || [],
    props.modelo.topoGuardado
  )
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
    pedido.value.topo ||
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
const semChave = (objeto, chave) =>
  Object.fromEntries(
    Object.entries(objeto).filter(([item]) => item !== String(chave))
  );
const comCartao = (indice, arquivo) => {
  const cartoes = semChave(props.valores.cartoes || {}, indice);
  atualizar({ cartoes: arquivo ? { ...cartoes, [indice]: arquivo } : cartoes });
};
// Sem arquivo escolhido, o topo sai dos valores: vai o aprovado com o modelo.
const comTopo = arquivo => {
  if (!ativo) return;
  const resto = semChave(props.valores, 'topo');
  emit('update', arquivo ? { ...resto, topo: arquivo } : resto);
};

// O arquivo sobe assim que é escolhido; enquanto sobe, a linha diz "Enviando".
// Chave: 'topo' ou o índice do cartão.
const enviando = ref({});
const erroDoEnvio = ref({});
const escolher = async (chave, { arquivo, local }, gravar) => {
  enviando.value = { ...enviando.value, [chave]: arquivo };
  erroDoEnvio.value = { ...erroDoEnvio.value, [chave]: '' };
  try {
    gravar(
      await api.subirArquivoDaCampanha(props.caixa, arquivoGuardado(local))
    );
  } catch (erro) {
    erroDoEnvio.value = {
      ...erroDoEnvio.value,
      [chave]: erro?.mensagem || t(`${NS}.ARQUIVO.ERRO`),
    };
  } finally {
    enviando.value = { ...enviando.value, [chave]: '' };
  }
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

    <ArquivoDaCampanha
      v-if="pedido.topo"
      data-formato-topo
      :titulo="t(`${NS}.TOPO.${pedido.topo.midia}`)"
      :midia="pedido.topo.midia"
      :guardado="pedido.topo.guardado"
      :escolhido="valores.topo || null"
      :enviando="enviando.topo || ''"
      :erro="erroDoEnvio.topo || ''"
      @escolhido="arquivo => escolher('topo', arquivo, comTopo)"
      @voltar="comTopo(null)"
    />

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
      :label="t(`${NS}.VALIDADE`, { zona: accountZoneLabel(timeZone) })"
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
          :data-formato-cartao="cartao.indice"
        >
          <ArquivoDaCampanha
            :titulo="t(`${NS}.CARTAO`, { n: cartao.indice + 1 })"
            :midia="cartao.midia"
            :guardado="cartao.guardado"
            :escolhido="valores.cartoes?.[cartao.indice] || null"
            :enviando="enviando[cartao.indice] || ''"
            :erro="erroDoEnvio[cartao.indice] || ''"
            @escolhido="
              arquivo =>
                escolher(cartao.indice, arquivo, novo =>
                  comCartao(cartao.indice, novo)
                )
            "
            @voltar="comCartao(cartao.indice, null)"
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
