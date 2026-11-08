// #2414 G21 (#2706) — o passo "prospecção": repetir uma busca do histórico da
// Prospecção e criar um card por empresa com WhatsApp, ou marcar que a empresa
// do contato não quer ser contatada. A régua é a do servidor
// (Autonomia::Automacao::PassoDeProspeccao): busca que quem salva vê, de 1 a
// 60 empresas, etapa do funil e etiquetas da conta.

// O teto da busca da Prospecção (SearchRunner::MAX_REQUESTED_LIMIT).
export const MAXIMO_DE_EMPRESAS = 60;

// Só o que cada escolha precisa: o "recusar" não leva os campos da busca.
export const comFaz = (passo, faz) =>
  faz === 'buscar'
    ? {
        ...passo,
        faz,
        quantas: passo.quantas || 20,
        etiquetas: passo.etiquetas || [],
      }
    : { id: passo.id, tipo: passo.tipo, faz };

// A busca concluída (ou servida do cache) do histórico serve; a que falhou ou
// ainda roda, não.
export const buscaQueServe = busca =>
  ['completed', 'cached'].includes(busca.status);

export const quantasServe = quantas =>
  Number.isInteger(quantas) && quantas >= 1 && quantas <= MAXIMO_DE_EMPRESAS;

export const prospeccaoPronta = passo => {
  if (passo?.faz === 'recusar') return true;
  if (passo?.faz !== 'buscar') return false;
  return (
    Number.isInteger(passo.busca_id) &&
    quantasServe(passo.quantas) &&
    Number.isInteger(passo.etapa_id)
  );
};

// O nome da busca na lista: o quê, onde e quando, como no histórico da tela.
export const nomeDaBusca = (busca, t) =>
  t('AUTOMACAO_LIVRE.PROSPECCAO.BUSCA_OPCAO', {
    oque: busca.query,
    onde: busca.location || t('AUTOMACAO_LIVRE.PROSPECCAO.SEM_LOCAL'),
    data: new Date(busca.created_at).toLocaleDateString(),
  });

const P = 'AUTOMACAO_LIVRE.PROSPECCAO';

// A frase da linha do passo.
export const fraseDaProspeccao = (passo, t) =>
  passo.faz === 'buscar'
    ? t(`${P}.FRASE_BUSCAR`, { quantas: passo.quantas || '' })
    : t(`${P}.FRASE_RECUSAR`);
