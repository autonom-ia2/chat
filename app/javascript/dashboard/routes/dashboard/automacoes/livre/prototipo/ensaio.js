// #2414 F0 — o ensaio: percorre a receita para um alvo de exemplo e diz, passo a
// passo, o que faria. Nada é executado. Esperas e decisões seguem o caminho que
// o alvo de exemplo traz (`alvo.caminhos`); sem ele, o primeiro caminho.
import { modeloPorId } from './frases';
import { passoSemVolta } from './receita';

const mensagemDoPasso = passo => {
  if (passo.tipo === 'mandar_mensagem') return passo.texto;
  if (passo.tipo === 'mandar_modelo') return modeloPorId(passo.modelo)?.texto;
  return null;
};

const percorrer = (passos, alvo, nivel) =>
  passos.reduce(
    (acc, passo) => {
      if (acc.parou) return acc;
      const linha = {
        passo,
        nivel,
        semVolta: passoSemVolta(passo),
        mensagem: mensagemDoPasso(passo),
      };
      if (passo.tipo === 'parar')
        return { linhas: [...acc.linhas, linha], parou: true };
      if (!passo.caminhos) return { ...acc, linhas: [...acc.linhas, linha] };

      const chave = alvo.caminhos?.[passo.id] || passo.caminhos[0]?.chave;
      const caminho = passo.caminhos.find(item => item.chave === chave);
      const dentro = caminho
        ? percorrer(caminho.passos, alvo, nivel + 1)
        : { linhas: [], parou: false };
      return {
        linhas: [...acc.linhas, { ...linha, caminho }, ...dentro.linhas],
        parou: dentro.parou,
      };
    },
    { linhas: [], parou: false }
  );

export const ensaiar = (receita, alvo) => {
  if (!receita || !alvo) return { comeca: false, linhas: [] };
  if (alvo.naoComecaChave) return { comeca: false, linhas: [] };
  return { comeca: true, linhas: percorrer(receita.passos, alvo, 0).linhas };
};
