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
// contador zerado some. Quem já estava aqui não é contador: é a frase de apoio
// de `quemJaEstava`, para o número de pessoas não aparecer duas vezes.
export const contadoresDaLeitura = leitura => {
  if (!leitura) return [];
  const { abertos, guardados, deixados } = contarProblemas(leitura.problemas);
  return [
    { chave: 'PRONTOS', count: (leitura.prontos ?? ZERO) + guardados },
    { chave: 'PRECISAM', count: abertos },
    { chave: 'SEM_TELEFONE', count: leitura.semTelefone ?? ZERO },
    { chave: 'NAO_E_APOLICE', count: leitura.naoEApolice?.length ?? ZERO },
    { chave: 'DEIXADOS', count: deixados },
  ].filter(({ count }) => count > ZERO);
};

// Das pessoas achadas, quem já estava na conta: todas, uma parte ou ninguém
// (`null`). A chave é do catálogo (TRAZER.CONFERIR.JA_ESTAVAM.<chave>).
export const quemJaEstava = leitura => {
  const jaEstavam = leitura?.jaEstavam ?? ZERO;
  if (jaEstavam <= ZERO) return null;
  const todas = jaEstavam >= (leitura.achei?.pessoas ?? ZERO);
  return { chave: todas ? 'TODAS' : 'PARTE', count: jaEstavam };
};
