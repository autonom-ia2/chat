<script setup>
// Gravação de áudio com a cara do WhatsApp (#1702): lixeira para cancelar, ponto
// vermelho com o tempo, a onda ao vivo, pausar/continuar e a seta que para e envia
// num toque. Por dentro é o gravador de sempre (AudioRecorder): mesma conversão para o
// formato que o WhatsApp aceita e o mesmo anexo de mensagem de voz.
// A conversa do Instagram (#2079) usa os mesmos controles com as cores do Direct (`visual`).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import AudioRecorder from 'dashboard/components/widgets/WootWriter/AudioRecorder.vue';

const props = defineProps({
  audioRecordFormat: { type: String, required: true },
  duracao: { type: String, default: '' },
  // Classes que mudam de um canal para o outro; sem nada, as do WhatsApp.
  visual: { type: Object, default: null },
});

const emit = defineEmits([
  'recorderProgressChanged',
  'finishRecord',
  'recordError',
  'micError',
  'play',
  'pause',
  'cancelar',
  'enviar',
]);

const { t } = useI18n();
// "0:04" como no app (o gravador de sempre manda "00:04").
const tempo = computed(() => {
  const texto = props.duracao || '0:00';
  return texto.length === 5 && texto.startsWith('0') ? texto.slice(1) : texto;
});
const gravador = ref(null);
const pausado = ref(false);

const pausarOuContinuar = () => {
  const plugin = gravador.value?.record;
  if (!plugin) return;
  // O estado vem do próprio gravador, não de um palpite local.
  if (plugin.isPaused()) {
    plugin.resumeRecording();
  } else {
    plugin.pauseRecording();
  }
  pausado.value = plugin.isPaused();
};

// A caixa de resposta chama os mesmos métodos do gravador de sempre.
const stopRecording = () => gravador.value?.stopRecording();
const playPause = () => gravador.value?.playPause();

defineExpose({ stopRecording, playPause });

const WHATSAPP = {
  barra: 'min-h-[52px]',
  botao:
    'grid place-content-center size-10 rounded-full flex-shrink-0 text-[#3B3B3B] dark:text-[#FAFAFA] hover:bg-[#0A0A0A]/5 dark:hover:bg-white/5 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#0A0A0A]',
  tempo: 'text-[20px] leading-6 text-[#0A0A0A] dark:text-[#FAFAFA]',
  onda: 'grayscale',
  pausa:
    'grid place-content-center size-9 rounded-full flex-shrink-0 text-[#C3002F] dark:text-[#F15C6D] hover:bg-[#FDE7EB] dark:hover:bg-[#F15C6D]/15 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#C3002F]',
  pausado: 'bg-[#FDE7EB] dark:bg-[#F15C6D]/15',
  enviar:
    'grid place-content-center size-10 rounded-full flex-shrink-0 bg-[#0A0A0A] hover:bg-[#2B2B2B] text-white dark:bg-[#21C063] dark:hover:bg-[#1DA855] dark:text-[#0A0A0A] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#0A0A0A]',
  iconeEnviar: 'i-ph-paper-plane-right-fill',
};
const classes = computed(() => props.visual || WHATSAPP);
</script>

<template>
  <!-- Como no app: tudo alinhado à direita dentro da pílula. Gravando: lixeira, ponto
       vermelho e tempo, a onda ao vivo, pausa vermelha e a seta preta. Pausado: o ponto
       fica cinza e a pausa vira o microfone vermelho para continuar. Ouvir antes de
       terminar não existe aqui: o gravador só entrega o áudio quando para. -->
  <div
    class="flex items-center justify-end gap-3 w-full pe-0"
    :class="classes.barra"
    role="group"
    :aria-label="t('CONVERSA_CANAL.GRAVACAO.GRAVANDO')"
    data-gravador-do-whatsapp
  >
    <button
      type="button"
      :class="classes.botao"
      :aria-label="t('CONVERSA_CANAL.GRAVACAO.CANCELAR')"
      :title="t('CONVERSA_CANAL.GRAVACAO.CANCELAR')"
      data-cancelar-gravacao
      @click="emit('cancelar')"
    >
      <Icon icon="i-ph-trash" class="size-6" />
    </button>
    <span class="flex items-center gap-2.5 flex-shrink-0">
      <span
        class="size-2.5 rounded-full"
        :class="pausado ? 'bg-[#A7A8A8]' : 'bg-[#EA0038] animate-pulse'"
        aria-hidden="true"
      />
      <span class="tabular-nums" :class="classes.tempo" aria-live="off">
        {{ tempo }}
      </span>
    </span>
    <!-- A onda do gravador de sempre, em cinza como a do app. -->
    <div
      class="w-[140px] max-md:w-[90px] flex-shrink min-w-0 h-10 overflow-hidden"
      :class="[classes.onda, pausado ? 'opacity-40' : 'opacity-60']"
    >
      <AudioRecorder
        ref="gravador"
        :audio-record-format="audioRecordFormat"
        :wave-height="36"
        @recorder-progress-changed="emit('recorderProgressChanged', $event)"
        @finish-record="emit('finishRecord', $event)"
        @record-error="emit('recordError', $event)"
        @mic-error="emit('micError', $event)"
        @play="emit('play')"
        @pause="emit('pause')"
      />
    </div>
    <button
      type="button"
      :class="[classes.pausa, pausado ? classes.pausado : '']"
      :aria-label="
        pausado
          ? t('CONVERSA_CANAL.GRAVACAO.CONTINUAR')
          : t('CONVERSA_CANAL.GRAVACAO.PAUSAR')
      "
      :title="
        pausado
          ? t('CONVERSA_CANAL.GRAVACAO.CONTINUAR')
          : t('CONVERSA_CANAL.GRAVACAO.PAUSAR')
      "
      data-pausar-gravacao
      @click="pausarOuContinuar"
    >
      <Icon
        :icon="pausado ? 'i-ph-microphone-fill' : 'i-ph-pause-fill'"
        class="size-6"
      />
    </button>
    <button
      type="button"
      :class="classes.enviar"
      :aria-label="t('CONVERSA_CANAL.GRAVACAO.ENVIAR')"
      :title="t('CONVERSA_CANAL.GRAVACAO.ENVIAR')"
      data-enviar-gravacao
      @click="emit('enviar')"
    >
      <Icon :icon="classes.iconeEnviar" class="size-5" />
    </button>
  </div>
</template>
