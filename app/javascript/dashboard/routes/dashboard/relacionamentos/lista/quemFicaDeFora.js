// #2894 — quem recebe a mensagem e quem fica de fora, sobre as pessoas
// marcadas. Cada pessoa conta uma vez só: quem pediu para não receber fica de
// fora por isso, mesmo sem telefone; sem telefone não há como mandar.
export const MOTIVOS_DE_FORA = {
  NAO_QUER: 'nao_quer',
  SEM_TELEFONE: 'sem_telefone',
};

const motivoDeFora = pessoa => {
  if (pessoa.opted_out_at) return MOTIVOS_DE_FORA.NAO_QUER;
  if (!pessoa.phone_number) return MOTIVOS_DE_FORA.SEM_TELEFONE;
  return null;
};

export const contaDaMensagem = (pessoas = []) => {
  const motivos = pessoas.map(motivoDeFora);
  const conta = motivo => motivos.filter(m => m === motivo).length;
  const naoQuer = conta(MOTIVOS_DE_FORA.NAO_QUER);
  const semTelefone = conta(MOTIVOS_DE_FORA.SEM_TELEFONE);
  return {
    total: pessoas.length,
    recebem: pessoas.length - naoQuer - semTelefone,
    fora: naoQuer + semTelefone,
    naoQuer,
    semTelefone,
  };
};
