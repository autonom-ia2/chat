// Pedaço da busca sem dono de frente: termo, quantidade e destino no CRM.
export const baseSlice = {
  formDefaults: () => ({
    query: '',
    requested_limit: 20,
  }),
  // O destino no CRM volta pelo useSearchCrm (applyCrmTarget).
  restoreForm: ({ form }, search) => {
    form.value = {
      ...form.value,
      query: search.query || '',
      requested_limit:
        Number(search.requested_limit) || form.value.requested_limit,
    };
  },
  toPayload: ({ form, crmForm }) => ({
    body: {
      query: form.value.query.trim(),
      requested_limit: Number(form.value.requested_limit),
      crm_pipeline_id: crmForm.value.pipeline_id,
      crm_stage_id: crmForm.value.stage_id,
    },
  }),
};
