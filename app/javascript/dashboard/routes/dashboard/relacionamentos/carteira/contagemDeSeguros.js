// #2897 — as contas da conferência de seguros (planilha, PDFs ou Agger), em
// funções puras: quantos seguros vão chegar, de quantas pessoas e os contadores
// do topo. Seguro em aberto ou deixado de fora não chega, e a pessoa dele também
// não (na demonstração, cada um é o único seguro da pessoa).
import { contarProblemas } from '../trazer/contagem';

const ZERO = 0;

export const totalDeSeguros = leitura => {
  const { guardados } = contarProblemas(leitura?.problemas);
  return (
    (leitura?.prontos ?? ZERO) + (leitura?.semTelefone ?? ZERO) + guardados
  );
};

export const pessoasDosSeguros = leitura => {
  const { abertos, deixados } = contarProblemas(leitura?.problemas);
  return Math.max(ZERO, (leitura?.achei?.pessoas ?? ZERO) - abertos - deixados);
};

// Cada contador vira uma chave do catálogo (TRAZER.CONFERIR.CONTADOR.<chave>);
// contador zerado some.
export const contadoresDaLeitura = leitura => {
  if (!leitura) return [];
  const { abertos, guardados, deixados } = contarProblemas(leitura.problemas);
  return [
    { chave: 'PRONTOS', count: (leitura.prontos ?? ZERO) + guardados },
    { chave: 'PRECISAM', count: abertos },
    { chave: 'SEM_TELEFONE', count: leitura.semTelefone ?? ZERO },
    { chave: 'JA_ESTAVAM', count: leitura.jaEstavam ?? ZERO },
    { chave: 'NAO_E_APOLICE', count: leitura.naoEApolice?.length ?? ZERO },
    { chave: 'DEIXADOS', count: deixados },
  ].filter(({ count }) => count > ZERO);
};
