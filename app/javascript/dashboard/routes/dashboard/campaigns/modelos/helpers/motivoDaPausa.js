// Por que a campanha parou (CampaignPause.reason_code e details, #1329) → motivo
// da tela. Usado pela tela de Modelos e pela lista de campanhas (#1332).
const MOTIVOS = {
  template_category_changed: 'tipo_mudou',
  template_structure_changed: 'modelo_mudou',
  template_missing: 'modelo_apagado',
  template_format_unsupported: 'formato_nao_vai',
};

export const motivoDaPausa = pausa => {
  if (pausa.reason_code === 'template_not_approved') {
    const status = String(pausa.details?.status || '').toUpperCase();
    if (status === 'REJECTED') return 'modelo_recusado';
    if (['PAUSED', 'DISABLED'].includes(status)) return 'modelo_pausado';
    return 'modelo_em_analise';
  }
  if (pausa.source === 'system') return 'nao_conferido';
  return MOTIVOS[pausa.reason_code] || 'outro';
};
