// #1702: com a pele do WhatsApp o balão de áudio não tem botão de baixar (como no
// app); o "Baixar" vai para o menu da mensagem. Sem pele, nada muda no menu.
import { computed } from 'vue';
import { ATTACHMENT_TYPES } from '../../message/constants';
import { usePele } from '../pele';
import { baixarPeloLink } from '../midia/enderecoParaBaixar';
import { nomeDoArquivo } from '../midia/tamanhoDoArquivo';

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

// Link direto, como o documento: o fetch do downloadFile falha sem CORS no bucket.
export const baixarAudio = anexo =>
  baixarPeloLink({ url: anexo.dataUrl, nome: nomeDoArquivo(anexo) });
