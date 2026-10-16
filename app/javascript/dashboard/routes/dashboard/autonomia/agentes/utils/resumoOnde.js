import { principalDaCaixa } from './ondeTrabalha';

// #1720 — o resumo "Onde e quando responde" da página do agente numa linha só:
// - "Atende primeiro no X e recebe quando alguém passar no Y";
// - "Recebe quando Clara passar no 5511944547873" (uma caixa só, com quem atende primeiro nela);
// - "Não atende em lugar nenhum."
// `primeiro`: nome da caixa em que atende primeiro (ou null) e `quantosPrimeiro`, a contagem quando o
// nome não está à mão (sem a leitura ou mais de uma caixa). `recebe`: linhas da L2 em que está na equipe.
const NS = 'AGENTS.JORNADA.PAGINA.BLOCO_ONDE';

const nomesDe = recebe => recebe.map(canal => canal.name).join(', ');

const soRecebe = (t, recebe) => {
  const principal = recebe.length === 1 ? principalDaCaixa(recebe[0]) : null;
  if (principal) {
    return t(`${NS}.RECEBE_DE`, {
      outro: principal.agent_name,
      canal: recebe[0].name,
    });
  }
  return t(`${NS}.RECEBE`, { caixas: nomesDe(recebe) }, recebe.length);
};

export const resumoOnde = (t, { primeiro, quantosPrimeiro, recebe = [] }) => {
  if (!quantosPrimeiro) {
    return recebe.length ? soRecebe(t, recebe) : t(`${NS}.NENHUM_LUGAR`);
  }
  const base = primeiro ? 'PRIMEIRO' : 'PRIMEIRO_N';
  if (!recebe.length) {
    return t(
      `${NS}.${base}`,
      { canal: primeiro, n: quantosPrimeiro },
      quantosPrimeiro
    );
  }
  return t(
    `${NS}.${base}_E_RECEBE`,
    { canal: primeiro, n: quantosPrimeiro, caixas: nomesDe(recebe) },
    primeiro ? recebe.length : quantosPrimeiro
  );
};
