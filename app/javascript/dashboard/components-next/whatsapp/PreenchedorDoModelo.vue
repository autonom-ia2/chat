<script setup>
// O preenchedor de modelo da conversa (#1705, épico #1320): o do Chatwoot
// (WhatsAppTemplateParser) mais o que ele não cobre.
//   - Cupom: o botão de enviar só libera com o código (1 a 15 letras). O do
//     Chatwoot, num modelo sem campo no texto nem mídia no topo, nem mostra a
//     caixa do código e libera o envio vazio: aqui a caixa aparece.
//   - Oferta com contagem: pede até quando vale, no fuso da conta, e manda
//     limited_time_offer.expiration_time_ms, que o servidor monta para a Meta
//     (Whatsapp::Templates::SendComponents).
// Mesma regra do servidor (envioNaConversa.js ↔ SendableFormat). Usado pela
// Nova conversa e pelo seletor de modelos da conversa; o arquivo do Chatwoot
// fica intacto.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import WhatsAppTemplateParser from './WhatsAppTemplateParser.vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { fusoDaConta, rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import { CODIGO_MAXIMO } from 'dashboard/routes/dashboard/campaigns/modelos/helpers/formatoNaCampanha';
import {
  comValidade,
  cuponsPreenchidos,
  envioCompleto,
  pedeValidade,
  validadeFaltando,
} from './envioNaConversa';

const props = defineProps({
  template: { type: Object, default: () => ({}) },
  sendRenderedContent: { type: Boolean, default: false },
});

const emit = defineEmits(['sendMessage', 'resetTemplate', 'back']);

const { t } = useI18n();
const { currentAccount } = useAccount();
const NS = 'MODELOS_WHATSAPP.CONVERSA';

const parser = ref(null);
const validade = ref('');
// Valor de cada botão que o preenchedor do Chatwoot não mostra (índice → texto).
const botoesProprios = ref({});
watch(
  () => props.template,
  () => {
    validade.value = '';
    botoesProprios.value = {};
  }
);

// O Chatwoot só mostra as caixas dos botões quando há campo no texto ou mídia.
const botoesNoParser = computed(
  () => Boolean(parser.value?.hasVariables || parser.value?.hasMediaHeader)
);
const botoesAPreencher = computed(() => {
  if (!parser.value || botoesNoParser.value) return [];
  return (parser.value.processedParams?.buttons || [])
    .map((botao, indice) => ({ ...botao, indice }))
    .filter(Boolean);
});
const paramsDoParser = computed(() => {
  const params = parser.value?.processedParams || {};
  if (botoesNoParser.value || !params.buttons) return params;
  return {
    ...params,
    buttons: params.buttons.map((botao, indice) =>
      botao
        ? { ...botao, parameter: botoesProprios.value[indice] ?? '' }
        : botao
    ),
  };
});

const fuso = computed(() => fusoDaConta(currentAccount.value));
const comOferta = computed(() => pedeValidade(props.template));
const faltaNaValidade = computed(() =>
  comOferta.value ? validadeFaltando(validade.value, fuso.value) : ''
);

const paramsDoEnvio = computed(() =>
  comValidade(props.template, paramsDoParser.value, validade.value, fuso.value)
);
const pronto = computed(
  () => Boolean(parser.value) && envioCompleto(props.template, paramsDoEnvio.value)
);
const faltaCupom = computed(
  () =>
    Boolean(parser.value) &&
    !cuponsPreenchidos(props.template, paramsDoParser.value)
);

// O preenchedor do Chatwoot monta o pedido; aqui entra a validade.
const aoMontar = payload => {
  emit('sendMessage', {
    ...payload,
    templateParams: {
      ...payload.templateParams,
      processed_params: paramsDoEnvio.value,
    },
  });
};

const sendMessage = () => {
  if (!pronto.value) return;
  parser.value.sendMessage();
};

defineExpose({
  isFormInvalid: computed(() => !pronto.value),
  renderedHeader: computed(() => parser.value?.renderedHeader || ''),
  renderedTemplate: computed(() => parser.value?.renderedTemplate || ''),
  sendMessage,
});
</script>

<template>
  <WhatsAppTemplateParser
    ref="parser"
    :template="template"
    :send-rendered-content="sendRenderedContent"
    @send-message="aoMontar"
    @reset-template="emit('resetTemplate')"
    @back="emit('back')"
  >
    <template #actions="{ resetTemplate, goBack, isValid }">
      <div class="flex flex-col gap-3 mb-4 empty:hidden">
        <Input
          v-for="botao in botoesAPreencher"
          :key="`botao-${botao.indice}`"
          :model-value="botoesProprios[botao.indice] || ''"
          :label="
            botao.type === 'copy_code'
              ? t(`${NS}.CUPOM`)
              : t('WHATSAPP_TEMPLATES.PARSER.BUTTON_PARAMETER')
          "
          custom-input-class="!h-11"
          :data-conversa-botao="botao.indice"
          @update:model-value="
            valor =>
              (botoesProprios = { ...botoesProprios, [botao.indice]: valor })
          "
        />
        <Input
          v-if="comOferta"
          v-model="validade"
          type="datetime-local"
          :label="t(`${NS}.VALIDADE`, { zona: rotuloDoFuso(fuso) })"
          :message="
            faltaNaValidade === 'VALIDADE_PASSADA'
              ? t(`${NS}.VALIDADE_PASSADA`)
              : t(`${NS}.VALIDADE_AJUDA`)
          "
          :message-type="
            faltaNaValidade === 'VALIDADE_PASSADA' ? 'error' : 'info'
          "
          wrap-message
          custom-input-class="!h-11"
          data-conversa-validade
        />
        <p
          v-if="faltaCupom"
          class="m-0 text-sm text-n-slate-11"
          data-conversa-cupom-falta
        >
          {{ t(`${NS}.CUPOM_FALTA`, { n: CODIGO_MAXIMO }) }}
        </p>
      </div>
      <slot
        name="actions"
        :send-message="sendMessage"
        :reset-template="resetTemplate"
        :go-back="goBack"
        :is-valid="isValid && pronto"
        :disabled="!pronto"
      />
    </template>
  </WhatsAppTemplateParser>
</template>
