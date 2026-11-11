// #2894 — quem recebe a mensagem e quem fica de fora, sobre as pessoas
// marcadas. Cada pessoa conta uma vez só, com a precedência da regra de envio
// da campanha: pediu para não receber, depois bloqueado, depois sem telefone.
// Na entrega real o número vem do backend (`campaign_reachable`): esta conta é só da demonstração, para não haver duas regras.
export const MOTIVOS_DE_FORA = {
  NAO_QUER: 'nao_quer',
  BLOQUEADO: 'bloqueado',
  SEM_TELEFONE: 'sem_telefone',
};

export const motivoDeFora = pessoa => {
  if (pessoa.opted_out_at) return MOTIVOS_DE_FORA.NAO_QUER;
  if (pessoa.blocked) return MOTIVOS_DE_FORA.BLOQUEADO;
  if (!pessoa.phone_number) return MOTIVOS_DE_FORA.SEM_TELEFONE;
  return null;
};

export const contaDaMensagem = (pessoas = []) => {
  const motivos = pessoas.map(motivoDeFora);
  const conta = motivo => motivos.filter(m => m === motivo).length;
  const naoQuer = conta(MOTIVOS_DE_FORA.NAO_QUER);
  const bloqueados = conta(MOTIVOS_DE_FORA.BLOQUEADO);
  const semTelefone = conta(MOTIVOS_DE_FORA.SEM_TELEFONE);
  const fora = naoQuer + bloqueados + semTelefone;
  return {
    total: pessoas.length,
    recebem: pessoas.length - fora,
    fora,
    naoQuer,
    bloqueados,
    semTelefone,
  };
};

// Quem recebe, na ordem em que foi marcado.
export const quemRecebe = (pessoas = []) =>
  pessoas.filter(pessoa => motivoDeFora(pessoa) === null);

// Quem fica de fora, agrupado por motivo, na ordem da regra de envio.
export const foraPorMotivo = (pessoas = []) =>
  Object.values(MOTIVOS_DE_FORA)
    .map(motivo => [
      motivo,
      pessoas.filter(pessoa => motivoDeFora(pessoa) === motivo),
    ])
    .filter(([, quem]) => quem.length > 0);
