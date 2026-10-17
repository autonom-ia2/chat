<script setup>
// Gravação de áudio com a cara do WhatsApp (#1702): lixeira para cancelar, ponto
// vermelho com o tempo, a onda ao vivo, pausar/continuar e a seta que para e envia
// num toque. Por dentro é o gravador de sempre (AudioRecorder): mesma conversão para o
// formato que o WhatsApp aceita e o mesmo anexo de mensagem de voz.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import AudioRecorder from 'dashboard/components/widgets/WootWriter/AudioRecorder.vue';

defineProps({
  audioRecordFormat: { type: String, required: true },
  duracao: { type: String, default: '' },
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

const BOTAO =
  'grid place-content-center size-10 rounded-full flex-shrink-0 text-[#54656F] dark:text-[#AEBAC1] hover:bg-[#111B21]/5 dark:hover:bg-white/5 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#00A884]';
</script>

<template>
  <div
    class="flex items-center gap-2 w-full min-h-[52px] px-1"
    role="group"
    :aria-label="t('CONVERSA_CANAL.GRAVACAO.GRAVANDO')"
    data-gravador-do-whatsapp
  >
    <button
      type="button"
      :class="BOTAO"
      :aria-label="t('CONVERSA_CANAL.GRAVACAO.CANCELAR')"
      :title="t('CONVERSA_CANAL.GRAVACAO.CANCELAR')"
      data-cancelar-gravacao
      @click="emit('cancelar')"
    >
      <Icon icon="i-ph-trash" class="size-6" />
    </button>
    <span
      class="size-2.5 rounded-full bg-[#F15C6D] flex-shrink-0"
      :class="{ 'animate-pulse': !pausado }"
      aria-hidden="true"
    />
    <span
      class="w-12 text-[17px] tabular-nums text-[#111B21] dark:text-[#E9EDEF] flex-shrink-0"
      aria-live="off"
    >
      {{ duracao || '00:00' }}
    </span>
    <!-- A onda do gravador de sempre, em cinza como a do app. -->
    <div class="flex-1 min-w-0 h-10 overflow-hidden grayscale opacity-60">
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
      :class="BOTAO"
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
        :class="{ 'text-[#F15C6D]': !pausado }"
      />
    </button>
    <button
      type="button"
      class="grid place-content-center size-11 rounded-full flex-shrink-0 bg-[#00A884] hover:bg-[#008F72] text-white dark:text-[#111B21] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#00A884]"
      :aria-label="t('CONVERSA_CANAL.GRAVACAO.ENVIAR')"
      :title="t('CONVERSA_CANAL.GRAVACAO.ENVIAR')"
      data-enviar-gravacao
      @click="emit('enviar')"
    >
      <Icon icon="i-ph-paper-plane-right-fill" class="size-5" />
    </button>
  </div>
</template>
