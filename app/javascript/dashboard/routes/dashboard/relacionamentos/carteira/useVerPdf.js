// #2897 — "Ver PDF" para as peças da carteira: abre o PDF do seguro
// (carteira/abrirPdf.js) e devolve a frase do que houve quando não abriu (texto
// vazio = abriu). Quem chama mostra a frase e relê o seguro: o motivo mais
// comum é o PDF ter sido tirado por outra pessoa.
import { useI18n } from 'vue-i18n';
import { abrirPdf } from './abrirPdf';
import { chaveDaRecusa, codigoDaRecusa } from './recusas';

const NAO_ABRIU = 'RELACIONAMENTOS_CARTEIRA.PDF.NAO_ABRIU';

export const useVerPdf = fonte => {
  const { t } = useI18n();

  return async id => {
    const falha = await abrirPdf(() => fonte.pdf(id));
    return falha ? t(chaveDaRecusa(codigoDaRecusa(falha), NAO_ABRIU)) : '';
  };
};
