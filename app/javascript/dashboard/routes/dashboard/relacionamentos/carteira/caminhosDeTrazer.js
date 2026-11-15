// #2900 (E7.3) — por onde a conta traz os seguros, além da planilha: os PDFs
// das apólices (`leituraDePdf: true` no resumo da carteira, decisão D4) e o
// Agger (`aggerDisponivel`), e se o login do Agger já foi aceito
// (`aggerLigado`). Uma pergunta só ao resumo. A demonstração não tem nenhum
// dos dois, e na dúvida (o resumo falhou) a resposta é não: a porta fica só
// com a planilha, como era.
import { carteiraFonteReal } from '../fonte/carteiraFonteReal';

export const SEM_CAMINHOS = Object.freeze({
  pdfs: false,
  agger: false,
  aggerLigado: false,
});

export const caminhosDeTrazer = async ({ demo = false, fonte = null } = {}) => {
  if (demo) return SEM_CAMINHOS;
  try {
    const resumo = await (fonte || carteiraFonteReal()).resumo();
    const agger = resumo?.aggerDisponivel === true;
    return {
      pdfs: resumo?.leituraDePdf === true,
      agger,
      aggerLigado: agger && resumo?.aggerLigado === true,
    };
  } catch {
    return SEM_CAMINHOS;
  }
};
