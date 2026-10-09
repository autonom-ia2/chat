/* global axios */
import ApiClient from '../ApiClient';

// Knowledge sources (RAG) for a given agent. The backend requires the params
// to be wrapped under `source` (`params.require(:source)`) with a valid
// `source_type` (link | pdf | xlsx | docx | json | txt | md). File uploads go
// as a top-level multipart `file` alongside the wrapped `source[...]` keys.
const FILE_SOURCE_TYPES = ['pdf', 'xlsx', 'docx', 'json', 'txt', 'md'];

// Infers the backend source_type from a file name extension, defaulting to
// `txt` for unknown/plain content (the backend re-validates the attachment).
const inferFileSourceType = name => {
  const ext = (name || '').split('.').pop()?.toLowerCase();
  return FILE_SOURCE_TYPES.includes(ext) ? ext : 'txt';
};

class AutonomiaSourcesAPI extends ApiClient {
  constructor() {
    super('autonomia/agents', { accountScoped: true });
  }

  get(agentId, { signal } = {}) {
    const endpoint = `${this.url}/${agentId}/sources`;
    return signal ? axios.get(endpoint, { signal }) : axios.get(endpoint);
  }

  reusable(agentId) {
    return axios.get(`${this.url}/${agentId}/sources/reusable`);
  }

  copy(agentId, sourceId) {
    return axios.post(`${this.url}/${agentId}/sources/copy`, {
      source_id: sourceId,
    });
  }

  // `descriptor` is either { url } for a link or { file } for an upload. Both
  // are mapped to the backend contract (wrapped `source[...]` + top-level file).
  create(agentId, descriptor = {}) {
    const endpoint = `${this.url}/${agentId}/sources`;

    if (descriptor.file) {
      const formData = new FormData();
      formData.append(
        'source[source_type]',
        inferFileSourceType(descriptor.file.name)
      );
      formData.append('source[reference]', descriptor.file.name);
      // saber/enviar group (backend gap #2). Sent when present; the backend
      // ignores it until the `kind` column exists.
      if (descriptor.kind) formData.append('source[kind]', descriptor.kind);
      formData.append('file', descriptor.file);
      return axios.post(endpoint, formData);
    }

    return axios.post(endpoint, {
      source: {
        source_type: 'link',
        reference: descriptor.url,
        external_link: descriptor.url,
        ...(descriptor.kind && { kind: descriptor.kind }),
      },
    });
  }

  delete(agentId, sourceId) {
    return axios.delete(`${this.url}/${agentId}/sources/${sourceId}`);
  }

  resync(agentId, sourceId) {
    return axios.post(`${this.url}/${agentId}/sources/${sourceId}/resync`);
  }
}

export default new AutonomiaSourcesAPI();
