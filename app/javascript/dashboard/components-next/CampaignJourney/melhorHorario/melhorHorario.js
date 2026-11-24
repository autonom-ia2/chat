// #3101 — "No melhor horário de cada cliente" na hora de começar a campanha. Quem já respondeu antes tem uma hora em
// que costuma responder (aprendida pelo servidor); essas pessoas recebem nessa hora, dentro das JANELA_HORAS depois do
// início e do horário permitido da conta. Quem ainda não tem hora recebe no início escolhido (agora ou data e hora).

export const JANELA_HORAS = 24;

/**
 * Quantas pessoas do público têm hora e quantas não têm.
 * `conhecidos` null = o servidor ainda está contando.
 */
export const coberturaDoPublico = ({ conhecidos, total }) => {
  if (conhecidos === null || conhecidos === undefined)
    return { estado: 'CONTANDO', conhecidos: 0, semHora: 0, total };
  const comHora = Math.min(Math.max(conhecidos, 0), total);
  if (!comHora)
    return { estado: 'NINGUEM', conhecidos: 0, semHora: total, total };
  return {
    estado: comHora === total ? 'TODOS' : 'PARTE',
    conhecidos: comHora,
    semHora: total - comHora,
    total,
  };
};
