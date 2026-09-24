// Pedaço da busca sem dono de frente: termo, quantidade e destino no CRM.
export const baseSlice = {
  formDefaults: () => ({
    query: '',
    requested_limit: 20,
  }),
  toPayload: ({ form, crmForm }) => ({
    body: {
      query: form.value.query.trim(),
      requested_limit: Number(form.value.requested_limit),
      crm_pipeline_id: crmForm.value.pipeline_id,
      crm_stage_id: crmForm.value.stage_id,
    },
  }),
};
