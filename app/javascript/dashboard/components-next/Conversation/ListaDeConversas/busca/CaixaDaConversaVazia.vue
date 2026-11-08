<script setup>
// #2211 — a caixa de resposta da conversa vazia, no pé da tela: a mesma caixa da conversa de
// verdade (ReplyBox), montada com as mesmas peças e na mesma ordem — ReplyTopPanel só com
// "Responder", o editor (WootMessageEditor), gravador e emojis do WhatsApp, anexos e a barra
// de baixo (ReplyBottomPanel), com a pele do canal (usePeleDaResposta). O ReplyBox em si lê a
// conversa aberta da store em todo canto; aqui ainda não existe conversa.
// O que ela pede segue o tipo da Nova conversa (novaConversa.TIPOS):
// - WhatsApp oficial: "Escolher o modelo" no lugar da caixa, com a explicação numa linha;
//   a escolha e os campos são os da Nova conversa (NovaConversaPronta), num painel que sobe;
// - e-mail: a caixa do e-mail novo do fork (NovaConversaCaixaDoEmail), com o assunto;
// - o resto: a caixa de resposta.
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import AttachmentPreview from 'dashboard/components/widgets/AttachmentsPreview.vue';
import ReplyTopPanel from 'dashboard/components/widgets/WootWriter/ReplyTopPanel.vue';
import ReplyBottomPanel from 'dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import GravadorDoWhatsapp from 'dashboard/components-next/conversa-canal/GravadorDoWhatsapp.vue';
import JanelaDeEmojis from 'dashboard/components-next/emoji/JanelaDeEmojis.vue';
import { usePeleDaResposta } from 'dashboard/components-next/conversa-canal/usePeleDaResposta';
import ContentTemplateSelector from 'dashboard/components-next/NewConversation/components/ContentTemplateSelector.vue';
import NovaConversaPronta from 'dashboard/components-next/NovaConversa/NovaConversaPronta.vue';
import NovaConversaCaixaDoEmail from 'dashboard/components-next/NovaConversa/NovaConversaCaixaDoEmail.vue';
import {
  TIPOS,
  aceitaAnexo,
  formatoDoAudio,
} from 'dashboard/components-next/NovaConversa/novaConversa';
import { useModeloUnico } from 'dashboard/components-next/NovaConversa/useModeloUnico';
import { useVozNaNovaConversa } from 'dashboard/components-next/NovaConversa/useVozNaNovaConversa';

const props = defineProps({
  canal: { type: Object, required: true },
  // A caixa como a store guarda (snake_case), a que a barra de baixo da resposta lê.
  caixa: { type: Object, default: () => ({}) },
  tipo: { type: String, required: true },
  comModelo: { type: Boolean, default: false },
  caixaDoWhatsapp: { type: Boolean, default: false },
  assinatura: { type: String, default: '' },
  comAssinatura: { type: Boolean, default: false },
  podeEnviar: { type: Boolean, default: false },
  enviando: { type: Boolean, default: false },
  // { nome, email } do contato, para o "Para" do e-mail.
  para: { type: Object, default: null },
  // O Assunto só na conversa nova; continuando uma conversa de e-mail, vale o assunto dela.
  comAssunto: { type: Boolean, default: true },
});
const emit = defineEmits([
  'enviar',
  'enviarPronta',
  'update:camposProntos',
  'update:textoDoModelo',
]);

const mensagem = defineModel('mensagem', { type: String, default: '' });
const assunto = defineModel('assunto', { type: String, default: '' });
const cc = defineModel('cc', { type: String, default: '' });
const bcc = defineModel('bcc', { type: String, default: '' });
const anexos = defineModel('anexos', { type: Array, default: () => [] });
const modelo = defineModel('modelo', { type: Object, default: null });

const { t } = useI18n();
const pronta = useTemplateRef('pronta');
const painelDeBaixo = useTemplateRef('painelDeBaixo');
const gravador = useTemplateRef('gravador');
const painelDoModelo = ref(false);

const modelosDaCaixa = useMapGetter('inboxes/getConversationWhatsAppTemplates');
const modelos = computed(() => modelosDaCaixa.value(props.canal.id));
useModeloUnico({ modelos, tipo: computed(() => props.tipo), modelo });

const email = computed(() => props.tipo === TIPOS.EMAIL);
const twilio = computed(() => props.tipo === TIPOS.WHATSAPP_TWILIO);
const { classesDaResposta, textoDoCampo } = usePeleDaResposta();

// A gravação e os anexos, os mesmos da gaveta "Enviar mensagem".
const {
  onFileUpload,
  gravando,
  duracao,
  gravar,
  cancelar,
  enviarGravacao,
  terminou,
  semMicrofone,
  falhou,
  progresso,
} = useVozNaNovaConversa({ anexos, gravador, aoAnexar: () => emit('enviar') });

// Anexo e microfone onde a conversa nova aceita: no WhatsApp (pelo número reserva também) e
// nos canais que mandam arquivo na criação (aceitaAnexo).
const comArquivo = computed(
  () =>
    props.caixaDoWhatsapp ||
    (!props.caixaDoWhatsapp && aceitaAnexo(props.canal))
);
const comMicrofone = computed(() => props.caixaDoWhatsapp);
const alternarGravacao = () => (gravando.value ? cancelar() : gravar());

// O emoji entra no ponto do cursor do editor, como na resposta.
const comEmojis = ref(false);
const inserirNoEditor = ref('');
const ancoraDosEmojis = () => painelDeBaixo.value?.barraDosEmojis?.() || null;
const escolherEmoji = emoji => {
  inserirNoEditor.value = emoji;
};

// Enter ou Cmd/Ctrl+Enter envia, conforme a preferência do atendente (a mesma da resposta);
// com um menu do editor aberto (respostas prontas, variáveis), a tecla é dele.
const { isEditorHotKeyEnabled } = useUISettings();
const atalho = useKbd(['$mod', '+', 'enter']);
const focado = ref(false);
const menusAbertos = ref(new Set());
const menu = nome => aberto => {
  const novos = new Set(menusAbertos.value);
  if (aberto) novos.add(nome);
  else novos.delete(nome);
  menusAbertos.value = novos;
};
const valeATecla = tecla =>
  focado.value && !menusAbertos.value.size && isEditorHotKeyEnabled(tecla);
useKeyboardEvents({
  Enter: {
    action: evento => {
      if (!valeATecla('enter')) return;
      evento.preventDefault();
      emit('enviar');
    },
    allowOnFocusedInput: true,
  },
  '$mod+Enter': {
    action: () => {
      if (valeATecla('cmd_enter')) emit('enviar');
    },
    allowOnFocusedInput: true,
  },
});
const rotuloDoEnviar = computed(() => {
  const tecla = isEditorHotKeyEnabled('cmd_enter')
    ? `(${atalho.value})`
    : '(↵)';
  return `${t('CONVERSATION.REPLYBOX.SEND')} ${tecla}`;
});
const vazio = computed(() => !mensagem.value.trim() && !anexos.value.length);

defineExpose({ montar: () => pronta.value?.montar() ?? null });
</script>

<template>
  <div data-caixa-da-conversa-vazia>
    <!-- WhatsApp oficial sem conversa aberta: só sai modelo. O botão fica no lugar da caixa. -->
    <div
      v-if="comModelo || twilio"
      class="relative flex flex-col gap-2 p-3 mx-2 mb-2 border border-n-weak rounded-xl bg-n-solid-1"
      :class="[classesDaResposta.caixa, classesDaResposta.soResposta]"
    >
      <p class="m-0 text-sm text-n-slate-11" data-linha-do-modelo>
        {{ t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.MODELO_LINHA') }}
      </p>
      <button
        type="button"
        data-escolher-modelo
        class="flex items-center justify-center w-full gap-2 px-4 text-sm font-medium border rounded-full shadow-sm border-n-strong min-h-12 bg-n-solid-3 text-n-blue-11 hover:bg-n-alpha-2"
        @click="painelDoModelo = true"
      >
        <span class="i-lucide-message-square-text size-5" aria-hidden="true" />
        {{ t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.ESCOLHER_MODELO') }}
      </button>
    </div>

    <!-- E-mail: a caixa do e-mail novo (Para, Cc/Cco, Assunto, texto e a barra). -->
    <div v-else-if="email" class="flex flex-col gap-2 px-2 pb-2">
      <NovaConversaCaixaDoEmail
        v-model:assunto="assunto"
        v-model:mensagem="mensagem"
        v-model:cc="cc"
        v-model:bcc="bcc"
        v-model:anexos="anexos"
        :com-assunto="comAssunto"
        :canal="canal"
        :assinatura="assinatura"
        :com-assinatura="comAssinatura"
        :para="para"
      />
      <div class="flex justify-end">
        <NextButton
          :label="t('CONVERSA_CANAL.EMAIL.ENVIAR_PARA', { nome: para?.nome })"
          icon="i-lucide-send-horizontal"
          trailing-icon
          sm
          data-enviar
          :disabled="!podeEnviar || enviando"
          @click="emit('enviar')"
        />
      </div>
    </div>

    <!-- A caixa de resposta: as peças do ReplyBox, na mesma ordem e com a pele. -->
    <div
      v-else
      class="relative mx-2 mb-2 border border-n-weak rounded-xl bg-n-solid-1"
      :class="{
        [classesDaResposta.caixa]: true,
        [classesDaResposta.soResposta]: true,
        [classesDaResposta.gravando]: gravando,
      }"
      data-caixa-de-resposta
    >
      <ReplyTopPanel so-resposta :has-content="!vazio" />
      <div class="relative px-3 py-0 -mt-px" :class="classesDaResposta.campo">
        <JanelaDeEmojis
          v-if="comEmojis"
          :ancora="ancoraDosEmojis()"
          @escolher="escolherEmoji"
          @fechar="comEmojis = false"
        />
        <GravadorDoWhatsapp
          v-if="gravando"
          ref="gravador"
          :audio-record-format="formatoDoAudio(canal)"
          :duracao="duracao"
          @recorder-progress-changed="progresso"
          @finish-record="terminou"
          @record-error="falhou"
          @mic-error="semMicrofone"
          @cancelar="cancelar"
          @enviar="enviarGravacao"
        />
        <WootMessageEditor
          v-else
          v-model="mensagem"
          :editor-id="`conversa-vazia-${canal.id}`"
          class="input popover-prosemirror-menu"
          :placeholder="textoDoCampo || t('CONVERSATION.FOOTER.MSG_INPUT')"
          :update-selection-with="inserirNoEditor"
          :min-height="4"
          :channel-type="caixa.channel_type"
          :medium="caixa.medium"
          data-mensagem
          @focus="focado = true"
          @blur="focado = false"
          @clear-selection="inserirNoEditor = ''"
          @toggle-user-mention="menu('mencao')($event)"
          @toggle-canned-menu="menu('prontas')($event)"
          @toggle-variables-menu="menu('variaveis')($event)"
          @toggle-macros-menu="menu('macros')($event)"
        />
        <div v-if="anexos.length" class="py-0 mb-2 bg-transparent">
          <AttachmentPreview
            class="mt-2"
            :attachments="anexos"
            @remove-attachment="lista => (anexos = lista)"
          />
        </div>
      </div>
      <ReplyBottomPanel
        ref="painelDeBaixo"
        sem-conversa
        :conversation-id="0"
        portal-slug=""
        :inbox="caixa"
        :on-send="() => emit('enviar')"
        :on-file-upload="onFileUpload"
        :toggle-emoji-picker="() => (comEmojis = !comEmojis)"
        :toggle-audio-recorder="alternarGravacao"
        :is-recording-audio="gravando"
        :recording-audio-duration-text="duracao"
        :show-file-upload="comArquivo"
        :show-audio-recorder="comMicrofone"
        :show-emoji-picker="comEmojis"
        :is-send-disabled="!podeEnviar || enviando"
        :send-button-text="rotuloDoEnviar"
        :campo-vazio="vazio"
        :message="mensagem"
        :new-conversation-modal-active="false"
      />
    </div>

    <!-- O painel do modelo sobe por cima da conversa: lista, campos e o Enviar. -->
    <div
      v-if="painelDoModelo"
      role="dialog"
      aria-modal="true"
      :aria-label="t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.ESCOLHER_MODELO')"
      data-painel-do-modelo
      class="absolute inset-x-0 bottom-0 z-10 flex flex-col max-h-[70vh] border-t shadow-xl rounded-t-2xl border-n-weak bg-n-solid-1"
      @keydown.esc.stop="painelDoModelo = false"
    >
      <header
        class="flex items-center justify-between gap-3 px-5 py-3 border-b border-n-weak"
      >
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.ESCOLHER_MODELO') }}
        </h2>
        <button
          type="button"
          class="flex items-center justify-center bg-transparent border-0 rounded-lg size-11 text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.FECHAR')"
          @click="painelDoModelo = false"
        >
          <span class="i-lucide-x size-5" aria-hidden="true" />
        </button>
      </header>
      <div class="flex-1 min-h-0 px-5 py-4 overflow-y-auto">
        <ContentTemplateSelector
          v-if="twilio"
          :inbox-id="canal.id"
          @send-message="emit('enviarPronta', $event)"
        />
        <NovaConversaPronta
          v-else
          ref="pronta"
          v-model="modelo"
          :modelos="modelos"
          @update:campos-prontos="emit('update:camposProntos', $event)"
          @update:texto="emit('update:textoDoModelo', $event)"
        />
      </div>
      <footer
        v-if="!twilio"
        class="flex justify-end px-5 py-3 border-t border-n-weak"
      >
        <button
          type="button"
          data-enviar
          class="px-5 text-sm font-medium text-white border-0 rounded-full min-h-11 bg-n-brand disabled:opacity-50"
          :disabled="!podeEnviar || enviando"
          @click="emit('enviar')"
        >
          {{
            enviando
              ? t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.ENVIANDO')
              : t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.ENVIAR')
          }}
        </button>
      </footer>
    </div>
  </div>
</template>
