<script setup>
// Embaixo do texto da resposta de e-mail (#1786): o que vai junto com ela.
// Histórico (Responder e Responder a todos): vai junto por padrão, como em qualquer
// e-mail corporativo (Rodrigo, 18/10). "Ver" mostra o e-mail citado; "Não enviar o
// histórico" tira só desta resposta, e "Pôr de volta" desfaz.
// Encaminhar: o cartão "Mensagem encaminhada" com o original formatado, só leitura.
// Os dois nascem fechados (Rodrigo, 19/10): "Ver" abre para quem quiser conferir.
// O servidor monta o HTML de verdade (ConversaCanal::CitacaoDoEmail).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { Letter } from 'vue-letter';
import { allowedCssProperties } from 'lettersanitizer';
import Icon from 'next/icon/Icon.vue';
import { remetenteDoEmail, semRastreio } from './dadosDoEmail';
import { htmlComCssSeguro } from './estiloSeguroDoEmail';

const props = defineProps({
  // A mensagem citada, como vem do store (snake_case).
  mensagem: { type: Object, required: true },
  tipo: {
    type: String,
    required: true,
    validator: v => ['historico', 'encaminhado'].includes(v),
  },
  desligado: { type: Boolean, default: false },
});
const emit = defineEmits(['alternar']);

const { t } = useI18n();
const aberto = ref(false);

const dados = computed(() => props.mensagem?.content_attributes?.email || {});
const quem = computed(
  () =>
    remetenteDoEmail({
      contentAttributes: { email: dados.value },
      sender: props.mensagem?.sender,
      recebido: true,
    }).nome
);
// O servidor só preenche html_content quando o e-mail tem parte HTML (MailPresenter).
// Sem ela, o corpo vai como texto, linha a linha: usado como HTML, virava uma linha só.
// O CSS do remetente não pode escapar do <style> ao passar pelo vue-letter (estiloSeguroDoEmail).
const html = computed(() =>
  htmlComCssSeguro(dados.value.html_content?.full || '')
);
const texto = computed(
  () => dados.value.text_content?.full || props.mensagem?.content || ''
);
const ehEncaminhado = computed(() => props.tipo === 'encaminhado');
const CSS_PERMITIDO = [
  ...allowedCssProperties,
  'transform',
  'transform-origin',
];

const LINK =
  'inline-flex items-center gap-1 min-h-11 px-3 rounded-full text-sm font-medium focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';
</script>

<template>
  <section
    class="mt-3 mb-1 rounded-xl border"
    :class="
      desligado
        ? 'border-dashed border-n-slate-6 bg-transparent'
        : 'border-n-weak bg-n-surface-1'
    "
    :data-citacao-da-resposta="tipo"
    :data-desligado="desligado || undefined"
  >
    <header
      class="flex flex-wrap items-center justify-between gap-x-2 ps-3 pe-1 py-1"
    >
      <p class="flex items-center gap-2 min-w-0 text-[13px]">
        <Icon
          :icon="
            ehEncaminhado
              ? 'i-lucide-forward'
              : desligado
                ? 'i-lucide-history'
                : 'i-lucide-check-circle-2'
          "
          class="size-4 flex-shrink-0"
          :class="
            desligado
              ? 'text-n-slate-10'
              : ehEncaminhado
                ? 'text-n-slate-11'
                : 'text-n-teal-10'
          "
        />
        <span
          class="truncate"
          :class="desligado ? 'text-n-slate-11' : 'text-n-slate-12'"
        >
          <template v-if="ehEncaminhado">
            {{ t('CONVERSA_CANAL.EMAIL.VAI_ENCAMINHADA', { nome: quem }) }}
          </template>
          <template v-else-if="desligado">
            {{ t('CONVERSA_CANAL.EMAIL.HISTORICO_NAO_VAI') }}
          </template>
          <template v-else>
            {{ t('CONVERSA_CANAL.EMAIL.HISTORICO_VAI', { nome: quem }) }}
          </template>
        </span>
      </p>
      <div class="flex items-center gap-1">
        <button
          v-if="!desligado"
          type="button"
          class="text-n-slate-11 hover:bg-n-alpha-2"
          :class="[LINK]"
          :aria-expanded="aberto"
          data-ver-citacao
          @click="aberto = !aberto"
        >
          {{
            aberto
              ? t('CONVERSA_CANAL.EMAIL.ESCONDER')
              : t('CONVERSA_CANAL.EMAIL.VER')
          }}
          <Icon
            :icon="aberto ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
            class="size-4"
          />
        </button>
        <button
          v-if="!ehEncaminhado"
          type="button"
          :class="[
            LINK,
            desligado
              ? 'text-n-blue-11 hover:bg-n-blue-3'
              : 'text-n-slate-11 hover:bg-n-alpha-2',
          ]"
          data-alternar-historico
          @click="emit('alternar')"
        >
          {{
            desligado
              ? t('CONVERSA_CANAL.EMAIL.POR_HISTORICO')
              : t('CONVERSA_CANAL.EMAIL.TIRAR_HISTORICO')
          }}
        </button>
      </div>
    </header>
    <div
      v-if="aberto && !desligado"
      class="max-h-72 overflow-y-auto mx-3 mb-3 ps-3 border-s-2 border-n-slate-6 text-sm text-n-slate-12"
      data-original-citado
    >
      <Letter
        class-name="prose prose-bubble !max-w-none letter-render"
        :html="html"
        :text="texto"
        :allowed-css-properties="CSS_PERMITIDO"
        :rewrite-external-resources="semRastreio"
        :rewrite-external-links="semRastreio"
      />
    </div>
  </section>
</template>
