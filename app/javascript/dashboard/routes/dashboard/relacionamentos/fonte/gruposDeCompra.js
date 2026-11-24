import { DIA_EM_MS } from './grupos';

// #3097 — os grupos por compra da lista de Relacionamentos (à moda RFV:
// quando comprou, quantas vezes e quanto). A compra é o card ganho num funil
// de Vender. A lista mostra os grupos por conversa ou por compra (`VISOES`);
// "Todos" abre as duas. As faixas são da conta (`FAIXAS_PADRAO` até alguém
// ajustar). Quem diz quem pertence é o servidor; a demonstração usa as mesmas
// regras daqui. O resumo de compras de uma pessoa:
//   { quantas, ultima_em (segundos), intervalo_medio_dias (null com 1 compra),
//     por_moeda: [{ moeda, total, quantas }] }
// #3168 — `MEUS`: os grupos que a pessoa guardou ("Meus grupos").
export const VISOES = { CONVERSA: 'conversa', COMPRA: 'compra', MEUS: 'meus' };

export const FAIXAS_PADRAO = Object.freeze({
  campeao_compras: 4,
  campeao_dias: 30,
  em_risco_dias: 90,
  perdido_dias: 180,
});

// Passou da hora de voltar: já comprou 2 vezes ou mais e está sem comprar há
// mais que o próprio costume, com esta folga (1,5 = metade a mais).
export const COMPRAS_PARA_TER_RITMO = 2;
export const FOLGA_DO_RITMO = 1.5;

export const GRUPOS_DE_COMPRA_IDS = Object.freeze({
  CAMPEOES: 'compra_campeoes',
  FIEIS: 'compra_fieis',
  NOVOS: 'compra_novos',
  PASSOU_DA_HORA: 'compra_passou_da_hora',
  EM_RISCO: 'compra_em_risco',
  PERDIDOS: 'compra_perdidos',
  NUNCA: 'compra_nunca',
});

const grupo = (id, chave) => ({
  id,
  nome: `RELACIONAMENTOS_COMPRAS.GRUPOS.${chave}.NOME`,
  explicacao: `RELACIONAMENTOS_COMPRAS.GRUPOS.${chave}.EXPLICACAO`,
  // O nome de uma pessoa só, para o selo da ficha ("Fiel", não "Fiéis").
  naFicha: `RELACIONAMENTOS_COMPRAS.GRUPOS.${chave}.NA_FICHA`,
});

const { CAMPEOES, FIEIS, NOVOS, PASSOU_DA_HORA, EM_RISCO, PERDIDOS, NUNCA } =
  GRUPOS_DE_COMPRA_IDS;

// Na ordem das pílulas: do melhor cliente para quem nunca comprou.
export const GRUPOS_DE_COMPRA = [
  grupo(CAMPEOES, 'CAMPEOES'),
  grupo(FIEIS, 'FIEIS'),
  grupo(NOVOS, 'NOVOS'),
  grupo(PASSOU_DA_HORA, 'PASSOU_DA_HORA'),
  grupo(EM_RISCO, 'EM_RISCO'),
  grupo(PERDIDOS, 'PERDIDOS'),
  grupo(NUNCA, 'NUNCA'),
];

export const diasSemComprar = (compras, agora) =>
  compras?.ultima_em ? (agora - compras.ultima_em * 1000) / DIA_EM_MS : null;

export const passouDaHora = (compras, agora) => {
  if (!compras || compras.quantas < COMPRAS_PARA_TER_RITMO) return false;
  const ritmo = compras.intervalo_medio_dias;
  return (
    Boolean(ritmo) && diasSemComprar(compras, agora) > ritmo * FOLGA_DO_RITMO
  );
};

// O grupo da pessoa: um só, para a ficha, a lista e as contagens concordarem.
// "Passou da hora de voltar" vale para quem tem costume e se atrasou, mas
// ainda não chegou ao limite de "sem comprar" (depois dele, vale o limite).
export const grupoPrincipal = (compras, agora, faixas = FAIXAS_PADRAO) => {
  if (!compras?.quantas) return NUNCA;
  const dias = diasSemComprar(compras, agora);
  if (dias > faixas.perdido_dias) return PERDIDOS;
  if (dias > faixas.em_risco_dias) return EM_RISCO;
  if (passouDaHora(compras, agora)) return PASSOU_DA_HORA;
  if (
    compras.quantas >= faixas.campeao_compras &&
    dias <= faixas.campeao_dias
  ) {
    return CAMPEOES;
  }
  return compras.quantas === 1 ? NOVOS : FIEIS;
};

export const pertenceAoGrupoDeCompra = (
  pessoa,
  grupoId,
  agora = Date.now(),
  faixas = FAIXAS_PADRAO
) => grupoPrincipal(pessoa.compras, agora, faixas) === grupoId;

export const ehGrupoDeCompra = grupoId =>
  Object.values(GRUPOS_DE_COMPRA_IDS).includes(grupoId);
