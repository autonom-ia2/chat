import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useRelationshipOpportunities } from './useRelationshipOpportunities';

export function useContactOpportunities({ accountId, contactId, enabled }) {
  return useRelationshipOpportunities({
    accountId,
    recordId: contactId,
    enabled,
    fetchOpportunities: (...args) =>
      CrmKanbanAPI.getContactOpportunities(...args),
  });
}
