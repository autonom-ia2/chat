import { ehCotacao, ehInterno } from './pagina';

// #1181 — o agente externo atende o cliente num canal conectado (WhatsApp, Instagram, e-mail…), e o
// cliente o vê com a foto desse canal: a foto da caixa (`avatar_url` do JSON de inbox). O interno
// (copiloto da equipe) e a cotação continuam com a foto própria.
export const usaFotoDoCanal = agente =>
  !ehInterno(agente) && !ehCotacao(agente);

// A caixa que dá a foto: a primeira das caixas do agente, na mesma ordem de "Responde no …".
// `canais` são as caixas da L2 deste agente; `caixas`, as da store `inboxes`.
// Devolve { nome, foto } (foto '' quando a caixa não tem) ou null (sem caixa ou agente sem canal).
export const caixaDaFoto = (agente, canais, caixas) => {
  if (!usaFotoDoCanal(agente)) return null;
  const [primeiro] = canais || [];
  if (!primeiro) return null;
  const caixa = (caixas || []).find(item => item.id === primeiro.inbox_id);
  return { nome: primeiro.name, foto: caixa?.avatar_url || '' };
};

// A foto que o painel mostra: a da caixa; sem ela, a própria; sem nenhuma, '' (a inicial).
export const fotoDoAgente = (agente, canais, caixas) =>
  caixaDaFoto(agente, canais, caixas)?.foto || agente?.avatar_url || '';
