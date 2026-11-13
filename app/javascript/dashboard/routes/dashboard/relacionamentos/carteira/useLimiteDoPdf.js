// #2897 — o maior PDF que a carteira guarda: o limite de anexo da instalação,
// o mesmo que o resto do painel usa (composables/useFileUpload.js) e que o
// servidor confere (Carteira::Pdf). A tela olha antes de enviar, para a pessoa
// não esperar o envio de um arquivo que será recusado.
import { useMapGetter } from 'dashboard/composables/store';
import {
  checkFileSizeLimit,
  resolveMaximumFileUploadSize,
} from 'shared/helpers/FileHelper';

// Devolve a pergunta "este arquivo cabe?". Arquivo sem tamanho conhecido (o de
// exemplo da demonstração) passa: quem decide é o servidor.
export const useLimiteDoPdf = () => {
  const globalConfig = useMapGetter('globalConfig/get');

  return arquivo => {
    if (!Number.isFinite(arquivo?.size)) return true;
    const limiteEmMb = resolveMaximumFileUploadSize(
      globalConfig.value?.maximumFileUploadSize
    );
    return checkFileSizeLimit(arquivo, limiteEmMb);
  };
};
