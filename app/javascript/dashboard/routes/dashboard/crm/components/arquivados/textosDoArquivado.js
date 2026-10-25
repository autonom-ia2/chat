import {
  STATUS_PILL_CLASSES,
  cardStatusLabel,
  countsAsSale,
  outcomeGroup,
  outcomeLabels,
} from '../../helpers/cardOutcome';

// Frases da linha de um card arquivado e do aviso depois de restaurar (#2095). Funções puras, com `t` e o formato
// de quem chama, para a linha, a gaveta e o aviso dizerem a mesma coisa.

// Os motivos que a IA grava ao arquivar (Crm::Ai::NaoENegocio::MOTIVOS e MOTIVO_TESTE).
const MOTIVO_DA_IA = {
  fora_do_negocio: 'FORA_DO_NEGOCIO',
  duplicado: 'DUPLICADO',
  teste: 'TESTE',
};

export const quemArquivou = (t, formato, linha) => {
  const dia = linha.archived_at
    ? formato.diaCurto(new Date(linha.archived_at))
    : '';
  const por = linha.archived_by || {};
  if (por.type === 'ai') {
    const motivo = MOTIVO_DA_IA[linha.archive_reason];
    return motivo
      ? t('CRM_ARQUIVADOS.LINHA.PELA_IA_MOTIVO', {
          dia,
          motivo: t(`CRM_ARQUIVADOS.MOTIVO_IA.${motivo}`),
        })
      : t('CRM_ARQUIVADOS.LINHA.PELA_IA', { dia });
  }
  if (por.type === 'user' && por.name)
    return t('CRM_ARQUIVADOS.LINHA.POR', { dia, nome: por.name });
  return dia ? t('CRM_ARQUIVADOS.LINHA.EM', { dia }) : '';
};

// O desfecho que o card arquivado guarda (Parte A): ganho, perdido, resolvido, cancelado. Vazio no card que estava
// em andamento.
export const desfechoDe = linha => linha?.desfecho || null;

// "Ganho", "Perdido" ou o nome próprio do funil: a aba da Lista para onde o card vai ao restaurar.
export const abaDoDesfecho = (t, desfecho, funil) => {
  const grupo = outcomeGroup(desfecho);
  return grupo ? outcomeLabels(t, funil)[grupo] : '';
};

export const seloDoDesfecho = (t, desfecho, funil) => ({
  rotulo: cardStatusLabel(t, desfecho, funil),
  classe: STATUS_PILL_CLASSES[desfecho] || 'bg-n-slate-3 text-n-slate-11',
});

// Venda que continua nos Números: card ganho, de funil que conta como venda.
export const ehVenda = (desfecho, funil) =>
  desfecho === 'won' && countsAsSale(funil);

export const valorDaLinha = (t, formato, linha) => {
  if (linha.value_hidden) return '';
  if (!Number(linha.value_cents)) return t('CRM_ARQUIVADOS.SEM_VALOR');
  return formato.dinheiro(linha.value_cents, linha.currency);
};

// O aviso depois de restaurar: onde o card está agora.
export const avisoDoRestaurado = (
  t,
  { nome, card, funil, retornosParados }
) => {
  const aba = abaDoDesfecho(t, card.status, funil);
  if (aba)
    return {
      texto: t('CRM_ARQUIVADOS.RESTAURADO.LISTA', { nome, aba }),
      lista: true,
    };
  const etapa = card.stage?.name || '';
  const base = t('CRM_ARQUIVADOS.RESTAURADO.QUADRO', { nome, etapa });
  if (!retornosParados) return { texto: base, lista: false };
  const retornos = t(
    'CRM_ARQUIVADOS.RESTAURADO.RETORNOS',
    { count: retornosParados },
    retornosParados
  );
  return { texto: `${base} ${retornos}`, lista: false, retornos: true };
};

// O nome que entra em "o card de {nome}" e "{nome} já tem outro card aberto" (decisão 6): o do cliente; sem contato,
// o título do card.
export const nomeDoCliente = card => card?.contact?.name || card?.title || '';

// Arquivar com Mover (#2145, opção 1 do Rodrigo): o card movido vai mesmo quando o cliente já tinha card aberto no
// destino. O resumo diz quantos clientes ficaram com mais de um aberto e lista até 3 nomes; o resto vira "mais N". Nulo sem nenhum.
export const avisoDosDoisAbertos = (t, juntar, resposta, funil) => {
  const grupo = resposta?.clients_with_two_open;
  const total = Number(grupo?.count || 0);
  if (!total) return null;
  const nomes = (grupo.items || [])
    .map(item => item.name)
    .filter(Boolean)
    .slice(0, 3);
  const resto = total - nomes.length;
  if (!nomes.length)
    return t(
      'CRM_ARQUIVADOS.FUNIL.MAIS_DE_UM_ABERTO',
      { count: total, funil },
      total
    );
  const lista = resto
    ? [...nomes, t('CRM_ARQUIVADOS.FUNIL.MAIS_N', { count: resto }, resto)]
    : nomes;
  return t(
    'CRM_ARQUIVADOS.FUNIL.MAIS_DE_UM_ABERTO_QUEM',
    { count: total, funil, nomes: juntar(lista) },
    total
  );
};
