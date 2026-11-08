// #1988 / #2211 — a gravação de voz antes de existir conversa (gaveta "Enviar mensagem" e
// conversa vazia da busca): o mesmo gravador e o mesmo anexo de mensagem de voz da caixa de
// resposta. Lixeira cancela; a seta para a gravação, anexa e só então pede o envio. Se o
// envio não sair, a gravação fica nos anexos, para tentar de novo pelo Enviar.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAnexarNaNovaConversa } from './useAnexarNaNovaConversa';

export function useVozNaNovaConversa({ anexos, gravador, aoAnexar }) {
  const { t } = useI18n();
  const { onFileUpload } = useAnexarNaNovaConversa(anexos);

  const vozes = computed(() =>
    anexos.value.filter(item => item.isVoiceMessage)
  );
  const gravando = ref(false);
  const duracao = ref('');
  const enviarAoAnexar = ref(false);

  const parar = () => {
    gravando.value = false;
    duracao.value = '';
  };
  const gravar = () => {
    enviarAoAnexar.value = false;
    gravando.value = true;
  };
  const cancelar = () => {
    enviarAoAnexar.value = false;
    parar();
  };
  const enviarGravacao = () => {
    enviarAoAnexar.value = true;
    gravador.value?.stopRecording();
  };
  const terminou = arquivo => {
    parar();
    if (arquivo) onFileUpload({ ...arquivo, isVoiceMessage: true });
  };
  const semMicrofone = () => {
    cancelar();
    useAlert(t('CONVERSA_CANAL.GRAVACAO.SEM_MICROFONE'));
  };
  const falhou = () => {
    cancelar();
    useAlert(t('CONVERSATION.REPLYBOX.AUDIO_CONVERSION_FAILED'));
  };
  const progresso = tempo => {
    duracao.value = tempo;
  };

  // O anexo chega depois de lido (e enviado, com envio direto): só então a seta envia.
  watch(
    () => vozes.value.length,
    (agora, antes) => {
      if (!enviarAoAnexar.value || agora <= antes) return;
      enviarAoAnexar.value = false;
      aoAnexar();
    }
  );

  return {
    onFileUpload,
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
  };
}
