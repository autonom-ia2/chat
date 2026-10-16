<script setup>
import { computed, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import ContentTemplateSelector from 'dashboard/components-next/NewConversation/components/ContentTemplateSelector.vue';
import NovaConversaOpcao from './NovaConversaOpcao.vue';
import NovaConversaTexto from './NovaConversaTexto.vue';
import NovaConversaPronta from './NovaConversaPronta.vue';
import NovaConversaEmail from './NovaConversaEmail.vue';
import NovaConversaAnexo from './NovaConversaAnexo.vue';
import { MODOS, TIPOS, aceitaAnexo } from './novaConversa';

// #1459 — "Sua mensagem": o que aparece depende do canal escolhido. Escrever
// é um campo simples; mensagem pronta é uma lista de modelos aprovados pelo
// WhatsApp; e-mail tem assunto e formatação.
const props = defineProps({
  canal: { type: Object, required: true },
  tipo: { type: String, required: true },
  assinatura: { type: String, default: '' },
  comAssinatura: { type: Boolean, default: false },
  podeCriarPronta: { type: Boolean, default: false },
  // #1505 — a mensagem entra numa conversa que já existe.
  continuando: { type: Boolean, default: false },
});

defineEmits([
  'update:camposProntos',
  'update:textoDoModelo',
  'enviarPronta',
  'criarPronta',
]);

const modo = defineModel('modo', { type: String, default: MODOS.ESCREVER });
const mensagem = defineModel('mensagem', { type: String, default: '' });
const assunto = defineModel('assunto', { type: String, default: '' });
const cc = defineModel('cc', { type: String, default: '' });
const bcc = defineModel('bcc', { type: String, default: '' });
const anexos = defineModel('anexos', { type: Array, default: () => [] });
const modelo = defineModel('modelo', { type: Object, default: null });

const P = 'NOVA_CONVERSA.MENSAGEM';
const pronta = ref(null);

const modelosDaCaixa = useMapGetter('inboxes/getConversationWhatsAppTemplates');
const modelos = computed(() => modelosDaCaixa.value(props.canal.id));

const livre = computed(() => props.tipo === TIPOS.WHATSAPP_LIVRE);
const comEscolha = computed(() => livre.value && modelos.value.length > 0);
const escolhePronta = computed(
  () =>
    props.tipo === TIPOS.WHATSAPP_PRONTA ||
    (comEscolha.value && modo.value === MODOS.PRONTA)
);
const escreve = computed(
  () => props.tipo === TIPOS.TEXTO || (livre.value && !escolhePronta.value)
);

// "Começar pronto": quando só dá para enviar mensagem pronta e há uma só
// aprovada, ela já vem marcada. Olha a quantidade, e não a lista, para não
// marcar de novo depois de a pessoa clicar em "Alterar".
watch(
  () => modelos.value.length,
  quantas => {
    if (props.tipo !== TIPOS.WHATSAPP_PRONTA || quantas !== 1) return;
    if (!modelo.value) [modelo.value] = modelos.value;
  },
  { immediate: true }
);

defineExpose({ montar: () => pronta.value?.montar() ?? null });
</script>

<template>
  <section data-nova-conversa-mensagem class="flex flex-col gap-4">
    <fieldset
      v-if="comEscolha"
      class="m-0 grid min-w-0 gap-3 border-0 p-0 sm:grid-cols-2"
    >
      <legend class="mb-3 p-0 text-base font-semibold text-n-slate-12">
        {{ $t(`${P}.TITULO`) }}
      </legend>
      <NovaConversaOpcao
        v-model="modo"
        name="nova-conversa-modo"
        :value="MODOS.ESCREVER"
        icone="i-lucide-pencil-line"
        :titulo="$t(`${P}.ESCREVER`)"
        :descricao="$t(`${P}.ESCREVER_TEXTO`)"
      />
      <NovaConversaOpcao
        v-model="modo"
        name="nova-conversa-modo"
        :value="MODOS.PRONTA"
        icone="i-lucide-message-square-text"
        :titulo="$t(`${P}.PRONTA`)"
        :descricao="$t(`${P}.PRONTA_TEXTO`)"
      />
    </fieldset>

    <header
      v-if="tipo === TIPOS.WHATSAPP_PRONTA || tipo === TIPOS.WHATSAPP_TWILIO"
      class="flex flex-col gap-1"
    >
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ $t(`${P}.SO_PRONTA_TITULO`) }}
      </h3>
      <p class="mb-0 text-[0.9375rem] leading-relaxed text-n-slate-11">
        {{
          $t(continuando ? `${P}.SO_PRONTA_CONVERSA` : `${P}.SO_PRONTA_TEXTO`)
        }}
      </p>
    </header>

    <NovaConversaTexto
      v-if="escreve"
      v-model="mensagem"
      :com-rotulo="!comEscolha"
    />

    <NovaConversaPronta
      v-else-if="escolhePronta"
      ref="pronta"
      v-model="modelo"
      :modelos="modelos"
      :pode-criar="podeCriarPronta"
      @update:campos-prontos="$emit('update:camposProntos', $event)"
      @update:texto="$emit('update:textoDoModelo', $event)"
      @criar="$emit('criarPronta')"
    />

    <!-- WhatsApp via Twilio: o seletor de hoje, sem redesenho. Ele mesmo
         confirma e envia a mensagem pronta escolhida. -->
    <ContentTemplateSelector
      v-else-if="tipo === TIPOS.WHATSAPP_TWILIO"
      :inbox-id="canal.id"
      @send-message="$emit('enviarPronta', $event)"
    />

    <NovaConversaEmail
      v-else-if="tipo === TIPOS.EMAIL"
      v-model:assunto="assunto"
      v-model:mensagem="mensagem"
      v-model:cc="cc"
      v-model:bcc="bcc"
      :canal="canal"
      :assinatura="assinatura"
      :com-assinatura="comAssinatura"
      :com-assunto="!continuando"
    />

    <NovaConversaAnexo
      v-if="aceitaAnexo(canal) && !escolhePronta"
      v-model="anexos"
    />
  </section>
</template>
