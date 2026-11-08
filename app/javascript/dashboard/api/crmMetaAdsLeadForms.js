/* global axios */
import ApiClient from './ApiClient';

// Lead forms of the Meta ads (#2195): each instant form of a connected Page
// sends whoever fills it to the pipeline and stage chosen for that form.
class CrmMetaAdsLeadFormsAPI extends ApiClient {
  constructor() {
    super('crm/meta_ads_lead_forms', { accountScoped: true });
  }

  // { pages: [{ id, name, receiving, forms: [{ id, name, status,
  //   leads_count, destination }] }], pipelines: [{ id, name, stages }],
  //   recent_leads: [...] | null }  (null: sem contact_view, a lista de quem chegou não vem)
  get() {
    return axios.get(this.url);
  }

  // Subscribes the app to the Page's leadgen field (pages_manage_metadata).
  receive(pageId) {
    return axios.post(`${this.url}/pages/${pageId}/receive`);
  }

  stopReceiving(pageId) {
    return axios.delete(`${this.url}/pages/${pageId}/receive`);
  }

  // importPast: also brings who filled the form in the last 90 days
  // (leads_retrieval) → { destination, imported }
  saveDestination(formId, { pipelineId, stageId, importPast }) {
    return axios.put(`${this.url}/forms/${formId}/destination`, {
      pipeline_id: pipelineId,
      stage_id: stageId,
      import_past: importPast,
    });
  }

  // Archived form: only brings who filled it in the last 90 days
  // (leads_retrieval); no destination is saved and the Page is not subscribed.
  // → { imported, pipeline_name, stage_name }. `imported` (and the form's
  // `brought.count` on the next GET) is who actually entered the pipeline,
  // not past_count: people already customers are not added again.
  bringPast(formId, { pipelineId, stageId }) {
    return axios.post(`${this.url}/forms/${formId}/bring_past`, {
      pipeline_id: pipelineId,
      stage_id: stageId,
    });
  }

  removeDestination(formId) {
    return axios.delete(`${this.url}/forms/${formId}/destination`);
  }
}

export default new CrmMetaAdsLeadFormsAPI();
