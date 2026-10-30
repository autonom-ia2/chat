<script setup>
// #1988 — a caixa "Sua mensagem" do WhatsApp (oficial com texto livre e comum/WAHA) na
// gaveta "Enviar mensagem", no padrão da caixa do e-mail (NovaConversaCaixaDoEmail):
// o texto, os anexos e, no pé fixo, a barra (NovaConversaBarraDoWhatsapp), com o aviso
// de assinatura logo acima. O microfone troca a barra pelo gravador da conversa
// (GravadorDoWhatsapp): lixeira cancela; a seta para a gravação, anexa como mensagem
// de voz e envia, como na caixa de resposta. Se o envio não sair, a gravação fica na
// caixa, com o player, para tentar de novo pelo Enviar.
import { computed, nextTick, useTemplateRef } from 'vue';
import AttachmentPreviews from 'dashboard/components-next/NewConversation/components/AttachmentPreviews.vue';
import AvisoDeAssinatura from 'dashboard/components-next/conversa-canal/email/AvisoDeAssinatura.vue';
import GravadorDoWhatsapp from 'dashboard/components-next/conversa-canal/GravadorDoWhatsapp.vue';
import NovaConversaBarraDoWhatsapp from './NovaConversaBarraDoWhatsapp.vue';
import { useVozNaNovaConversa } from './useVozNaNovaConversa';
import { formatoDoAudio } from './novaConversa';

defineProps({
  canal: { type: Object, required: true },
  assinatura: { type: String, default: '' },
  comAssinatura: { type: Boolean, default: false },
  comRotulo: { type: Boolean, default: true },
});
const emit = defineEmits(['enviar']);

const mensagem = defineModel('mensagem', { type: String, default: '' });
const anexos = defineModel('anexos', { type: Array, default: () => [] });

const campo = useTemplateRef('campo');
const gravador = useTemplateRef('gravador');

// A gravação: o mesmo gravador e o mesmo anexo de mensagem de voz da caixa de resposta.
const {
  vozes,
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

// O emoji entra no ponto do cursor, e o cursor fica logo depois dele.
const inserir = async texto => {
  const atual = mensagem.value;
  const inicio = campo.value?.selectionStart ?? atual.length;
  const fim = campo.value?.selectionEnd ?? inicio;
  mensagem.value = atual.slice(0, inicio) + texto + atual.slice(fim);
  await nextTick();
  const depois = inicio + texto.length;
  campo.value?.focus();
  campo.value?.setSelectionRange(depois, depois);
};

const arquivos = computed(() =>
  anexos.value.filter(item => !item.isVoiceMessage)
);
const trocarArquivos = lista => {
  anexos.value = [...lista, ...vozes.value];
};
const tirarVoz = voz => {
  anexos.value = anexos.value.filter(item => item !== voz);
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <label
      for="nova-conversa-texto"
      class="mb-0 text-base font-semibold text-n-slate-12"
      :class="{ 'sr-only': !comRotulo }"
    >
      {{ $t('NOVA_CONVERSA.MENSAGEM.CAMPO') }}
    </label>
    <div
      class="flex max-h-[calc(100dvh-19rem)] flex-col rounded-2xl border border-n-weak bg-n-surface-1 shadow-[0_1px_2px_rgba(0,0,0,0.12),0_1px_3px_1px_rgba(0,0,0,0.06)] transition focus-within:border-n-blue-8"
      data-caixa-do-whatsapp
    >
      <div
        class="min-h-0 flex-1 overflow-y-auto overscroll-contain [overflow-anchor:none]"
      >
        <!-- Os "!" vencem o estilo global de <textarea> do painel (borda e altura). -->
        <textarea
          id="nova-conversa-texto"
          ref="campo"
          v-model="mensagem"
          data-foco
          rows="6"
          :placeholder="$t('NOVA_CONVERSA.MENSAGEM.PLACEHOLDER')"
          class="!mb-0 !h-auto min-h-[8.5rem] w-full resize-none !rounded-t-2xl !border-0 !bg-transparent !px-4 !pt-3 !pb-2 !text-base leading-relaxed text-n-slate-12 !shadow-none !outline-none placeholder:text-n-slate-10"
        />
        <ul
          v-if="vozes.length"
          class="m-0 flex list-none flex-col gap-2 px-4 pb-2"
          data-vozes-do-whatsapp
        >
          <li
            v-for="voz in vozes"
            :key="voz.resource.id"
            class="flex items-center gap-2"
          >
            <span
              class="i-ph-microphone-fill size-5 shrink-0 text-n-teal-10"
              aria-hidden="true"
            />
            <audio
              controls
              :src="voz.thumb"
              :aria-label="$t('NOVA_CONVERSA.MENSAGEM.VOZ')"
              class="h-10 min-w-0 flex-1"
            />
            <button
              type="button"
              class="grid size-11 shrink-0 place-content-center rounded-full text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :aria-label="$t('NOVA_CONVERSA.MENSAGEM.TIRAR_VOZ')"
              :title="$t('NOVA_CONVERSA.MENSAGEM.TIRAR_VOZ')"
              data-tirar-voz
              @click="tirarVoz(voz)"
            >
              <span class="i-ph-trash size-5" aria-hidden="true" />
            </button>
          </li>
        </ul>
        <AttachmentPreviews
          v-if="arquivos.length"
          :attachments="arquivos"
          class="!px-4 !pt-2 !pb-3"
          data-anexos-do-whatsapp
          @update:attachments="trocarArquivos"
        />
      </div>

      <div
        class="flex-shrink-0 rounded-b-2xl border-t border-n-weak bg-n-surface-1"
        data-pe-do-whatsapp
      >
        <div v-if="comAssinatura && !assinatura" class="px-3 pt-2">
          <AvisoDeAssinatura />
        </div>
        <div v-if="gravando" class="px-3 py-1">
          <GravadorDoWhatsapp
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
        </div>
        <NovaConversaBarraDoWhatsapp
          v-else
          v-model:anexos="anexos"
          :canal="canal"
          :com-assinatura="comAssinatura"
          @inserir="inserir"
          @gravar="gravar"
        />
      </div>
    </div>
  </div>
</template>
