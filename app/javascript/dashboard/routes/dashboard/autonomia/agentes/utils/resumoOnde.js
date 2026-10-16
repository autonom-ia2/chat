// #1720 — o resumo "Onde e quando responde" da página do agente numa linha só, com o "quando" curto
// depois de " · ":
// - "Atende primeiro no X e recebe no Y quando alguém passar · sempre";
// - "Recebe no 5511944547873 quando alguém passar a conversa · sempre";
// - "Não atende em lugar nenhum."
// `primeiro`: nome da caixa em que atende primeiro (ou null) e `quantosPrimeiro`, a contagem quando o
// nome não está à mão (sem a leitura ou mais de uma caixa). `recebe`: linhas da L2 em que está na
// equipe. `quando`: a frase curta da janela (PAGINA.QUANDO).
const NS = 'AGENTS.JORNADA.PAGINA.BLOCO_ONDE';

const nomesDe = recebe => recebe.map(canal => canal.name).join(', ');

export const resumoOnde = (
  t,
  { primeiro, quantosPrimeiro, recebe = [], quando }
) => {
  const caixas = nomesDe(recebe);
  if (!quantosPrimeiro) {
    return recebe.length
      ? t(`${NS}.RECEBE`, { caixas, quando }, recebe.length)
      : t(`${NS}.NENHUM_LUGAR`);
  }
  const base = primeiro ? 'PRIMEIRO' : 'PRIMEIRO_N';
  const valores = { canal: primeiro, n: quantosPrimeiro, caixas, quando };
  if (!recebe.length) return t(`${NS}.${base}`, valores, quantosPrimeiro);
  return t(
    `${NS}.${base}_E_RECEBE`,
    valores,
    primeiro ? recebe.length : quantosPrimeiro
  );
};
