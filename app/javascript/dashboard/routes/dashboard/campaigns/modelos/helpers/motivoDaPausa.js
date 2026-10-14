// Por que a campanha parou (CampaignPause.reason_code e details, #1329) → motivo
// da tela. Usado pela tela de Modelos e pela lista de campanhas (#1332).
const MOTIVOS = {
  template_category_changed: 'tipo_mudou',
  template_structure_changed: 'modelo_mudou',
  template_missing: 'modelo_apagado',
  template_format_unsupported: 'formato_nao_vai',
  // #1382: topo com mídia sem link e sem o arquivo guardado no modelo.
  template_media_missing: 'arquivo_do_topo',
  // #1334: a validade da oferta passou antes do envio.
  template_offer_expired: 'oferta_vencida',
};
// Do sistema, mas com motivo que a pessoa resolve (não é "não deu para conferir").
const DO_SISTEMA_COM_MOTIVO = ['template_missing'];

export const motivoDaPausa = pausa => {
  if (pausa.reason_code === 'template_not_approved') {
    const status = String(pausa.details?.status || '').toUpperCase();
    if (status === 'REJECTED') return 'modelo_recusado';
    if (['PAUSED', 'DISABLED'].includes(status)) return 'modelo_pausado';
    return 'modelo_em_analise';
  }
  if (
    pausa.source === 'system' &&
    !DO_SISTEMA_COM_MOTIVO.includes(pausa.reason_code)
  )
    return 'nao_conferido';
  return MOTIVOS[pausa.reason_code] || 'outro';
};
