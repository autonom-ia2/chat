/* global axios */
import ApiClient from './ApiClient';

class CustomRole extends ApiClient {
  constructor() {
    super('custom_roles', { accountScoped: true });
  }

  // Função com gente: o servidor pede para onde as pessoas vão (#2185), outra função ou 'none' (agente comum).
  delete(id, destinationRoleId) {
    const params = destinationRoleId
      ? { destination_role_id: destinationRoleId }
      : {};
    return axios.delete(`${this.url}/${id}`, { params });
  }
}

export default new CustomRole();
