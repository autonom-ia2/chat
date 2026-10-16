// #1702: com a pele do WhatsApp o balão de áudio não tem botão de baixar (como no
// app); o "Baixar" vai para o menu da mensagem. Sem pele, nada muda no menu.
import { computed } from 'vue';
import { downloadFile } from '@chatwoot/utils';
import { ATTACHMENT_TYPES } from '../../message/constants';
import { usePele } from '../pele';

export const useAudioParaBaixar = anexos => {
  const pele = usePele();
  return computed(() => {
    if (!pele.value) return null;
    return (
      (anexos.value || []).find(
        anexo => anexo.fileType === ATTACHMENT_TYPES.AUDIO
      ) || null
    );
  });
};

export const baixarAudio = anexo =>
  downloadFile({
    url: anexo.dataUrl,
    type: anexo.fileType,
    extension: anexo.extension,
  });
