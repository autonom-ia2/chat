// #2899 (E6.4) — a conta lê PDF? Só com `leituraDePdf: true` no resumo da
// carteira (decisão D4); a demonstração não lê, e na dúvida (o resumo falhou)
// a resposta é não: a tela fica como era, sem nada sobre leitura.
import { carteiraFonteReal } from '../fonte/carteiraFonteReal';

export const leituraDePdf = async ({ demo = false, fonte = null } = {}) => {
  if (demo) return false;
  try {
    const resumo = await (fonte || carteiraFonteReal()).resumo();
    return resumo?.leituraDePdf === true;
  } catch {
    return false;
  }
};
