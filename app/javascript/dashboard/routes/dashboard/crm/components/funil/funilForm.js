// #1384 — o formulário da gaveta de funil: o que se lê do funil salvo e o que
// se manda ao salvar. O contrato com o servidor é o mesmo de antes do #1384.

export const lerMetaSync = (metaSync = {}) => ({
  enabled: Boolean(metaSync.enabled),
  datasetId: metaSync.dataset_id || '',
  pixelId: metaSync.pixel_id || '',
  events: {
    won: metaSync.events?.won ?? true,
    lost: metaSync.events?.lost ?? false,
    moved: metaSync.events?.moved ?? false,
  },
});

export const lerGoogleSync = (googleSync = {}) => ({
  enabled: Boolean(googleSync.enabled),
  events: {
    won: googleSync.events?.won ?? true,
    lost: googleSync.events?.lost ?? false,
    moved: googleSync.events?.moved ?? false,
  },
  conversionNames: { won: googleSync.conversion_names?.won || '' },
});

export const lerResultados = (outcomeLabels = {}) => ({
  success: outcomeLabels.success || '',
  failure: outcomeLabels.failure || '',
});

// O nome do resultado quando a pessoa deixa em branco.
export const resultadosPadrao = (venda, t) =>
  venda
    ? {
        success: t('CRM_KANBAN.DRAWER.STATUS_WON'),
        failure: t('CRM_KANBAN.DRAWER.STATUS_LOST'),
      }
    : {
        success: t('CRM_KANBAN.DRAWER.STATUS_RESOLVED'),
        failure: t('CRM_KANBAN.DRAWER.STATUS_CANCELLED'),
      };

const CENTAVOS = 100;
export const metaDoMes = centavos =>
  centavos ? Number(centavos) / CENTAVOS : '';

// Board stages expose funnel_stage_type top-level; stages API payloads carry it
// inside metadata. Read both so opening the drawer never wipes the mapping.
// total_cards_count conta todos os status (aberto, ganho, perdido, arquivado):
// é o que diz ao apagar que uma etapa "com 0 cards" não está vazia.
export const copiarEtapa = (etapa, cor) => ({
  editorKey: crypto.randomUUID(),
  id: etapa.id,
  name: etapa.name || '',
  description: etapa.description || '',
  color: etapa.color || cor,
  funnel_stage_type:
    etapa.funnel_stage_type || etapa.metadata?.funnel_stage_type || '',
  total_cards_count: etapa.total_cards_count ?? 0,
});

// "Avisar também quando o cliente chegar em…": uma etapa só. A escolhida
// passa a valer como "quer comprar" (qualified) para os anúncios; só a etapa
// que já era "quer comprar" deixa de ser. Os outros tipos (lead, oportunidade,
// negociação) ficam como estão. Sem escolha, nenhuma etapa fica "quer comprar".
export const TIPO_AVISO = 'qualified';
export const avisarEm = (etapas, chave) =>
  etapas.forEach(etapa => {
    if (etapa.editorKey === chave) {
      Object.assign(etapa, { funnel_stage_type: TIPO_AVISO });
    } else if (etapa.funnel_stage_type === TIPO_AVISO) {
      Object.assign(etapa, { funnel_stage_type: '' });
    }
  });
export const etapaDoAviso = etapas =>
  etapas.find(etapa => etapa.funnel_stage_type === TIPO_AVISO) || null;

export const payloadDoFunil = ({ form, pipeline, editando, ia }) => ({
  pipeline: {
    id: pipeline?.id,
    name: form.name.trim(),
    description: form.description.trim(),
    when_to_use: form.whenToUse.trim(),
    is_default: pipeline?.is_default ?? !editando,
    position: pipeline?.position || 1,
    counts_as_sale: form.countsAsSale,
    outcome_labels: {
      success: form.outcomeLabels.success.trim(),
      failure: form.outcomeLabels.failure.trim(),
    },
    goal: {
      monthly_target_cents:
        Number(form.monthlyTarget) > 0
          ? Math.round(Number(form.monthlyTarget) * CENTAVOS)
          : 0,
      currency: 'BRL',
    },
    // Always emitted so toggling Meta sync off persists enabled:false.
    meta_sync: {
      enabled: form.metaSync.enabled,
      events: { ...form.metaSync.events },
      dataset_id: form.metaSync.datasetId.trim() || null,
      pixel_id: form.metaSync.pixelId || null,
    },
    // Always emitted so toggling Google sync off persists enabled:false.
    google_sync: {
      enabled: form.googleSync.enabled,
      events: { ...form.googleSync.events },
      conversion_names: {
        won: form.googleSync.conversionNames.won.trim() || null,
      },
    },
  },
  stages: form.stages.map((stage, index) => ({
    id: stage.id,
    color: stage.color,
    total_cards_count: stage.total_cards_count,
    name: stage.name.trim(),
    description: stage.description?.trim() || '',
    ...(!stage.id && ia && stage.aiCriteria !== undefined
      ? { aiCriteria: stage.aiCriteria.trim() }
      : {}),
    position: index + 1,
    funnel_stage_type: stage.funnel_stage_type || null,
  })),
});
