import { chaveDoErroDeAcesso } from '../../helpers/accessErrors';

// O motivo de uma recusa do servidor, em frase de quem usa (#2095). A API do CRM responde com um código estável em
// `error` (ex.: crm.card_restore_pipeline_archived); a tela traduz cada um. Sem resposta, é a internet. Código que a
// tela não conhece vira "o sistema recusou", nunca o texto cru do Rails.
const CODIGOS = {
  'crm.card_restore_not_archived': 'NAO_ARQUIVADO',
  'crm.card_restore_pipeline_archived': 'FUNIL_ARQUIVADO',
  'crm.card_restore_conflict': 'CONFLITO',
  'crm.card_close_archived': 'FECHAR_ARQUIVADO',
  'crm.pipeline_restore_not_archived': 'FUNIL_NAO_ARQUIVADO',
  'crm.pipeline_archive_already_archived': 'FUNIL_JA_ARQUIVADO',
  'crm.pipeline_archive_invalid_target': 'DESTINO_INVALIDO',
  'crm.pipeline_archive_invalid_inboxes_target': 'DESTINO_CAIXAS_INVALIDO',
  'crm.pipeline_archive_invalid_new_default': 'PRINCIPAL_INVALIDO',
  'crm.pipeline_archive_last_active': 'ULTIMO_FUNIL',
  'crm.pipeline_archive_only_default': 'UNICO_PRINCIPAL',
  'crm.pipeline_archive_changed': 'FUNIL_MUDOU',
  forbidden: 'SEM_PERMISSAO',
};

export const motivoDoErro = (t, error) => {
  const resposta = error?.response;
  if (!resposta) return t('CRM_ARQUIVADOS.ERROS.SEM_CONEXAO');
  const codigo = resposta.data?.error;
  if (CODIGOS[codigo]) return t(`CRM_ARQUIVADOS.ERROS.${CODIGOS[codigo]}`);
  const acesso = chaveDoErroDeAcesso(error);
  if (acesso) return t(acesso);
  if (resposta.status === 401 || resposta.status === 403)
    return t('CRM_ARQUIVADOS.ERROS.SEM_PERMISSAO');
  // A recusa do arquivar funil já vem traduzida pela Parte A (crm_pipelines.*.yml).
  if (typeof resposta.data?.message === 'string' && resposta.data.message)
    return resposta.data.message;
  return t('CRM_ARQUIVADOS.ERROS.RECUSOU');
};

// O motivo de um card pulado no "Restaurar (N)".
export const motivoDoPulado = (t, codigo) =>
  t(`CRM_ARQUIVADOS.ERROS.${CODIGOS[codigo] || 'RECUSOU'}`);
