import {
  crmPresenceDetail,
  crmSendableLeads,
  hasLeadStatus,
  isCrmSendable,
  isLeadDiscarded,
  isLeadInCrm,
} from '../../utils/leadCrmPresence';

const presence = {
  card_id: 555,
  pipeline_name: 'Vendas',
  stage_name: 'Novo',
  owner_name: 'Ana Souza',
};

describe('leadCrmPresence', () => {
  it('lead com card está no CRM; sem card, não', () => {
    expect(isLeadInCrm({ crm_card_id: 555 })).toBe(true);
    expect(isLeadInCrm({ crm_card_id: null })).toBe(false);
  });

  it('só o status discarded é descartado', () => {
    expect(isLeadDiscarded({ status: 'discarded' })).toBe(true);
    expect(isLeadDiscarded({ status: 'new_lead' })).toBe(false);
  });

  it('o envio ao CRM deixa de fora quem já está lá e quem foi descartado', () => {
    const fresh = { id: 1, crm_card_id: null, status: 'new_lead' };
    const inCrm = { id: 2, crm_card_id: 555, status: 'new_lead' };
    const discarded = { id: 3, crm_card_id: null, status: 'discarded' };

    expect(isCrmSendable(fresh)).toBe(true);
    expect(crmSendableLeads([fresh, inCrm, discarded])).toEqual([fresh]);
  });

  it('a faixa aparece para lead no CRM ou descartado, e só para eles', () => {
    expect(hasLeadStatus({ crm_card_id: 555, status: 'new_lead' })).toBe(true);
    expect(hasLeadStatus({ crm_card_id: null, status: 'discarded' })).toBe(
      true
    );
    expect(hasLeadStatus({ crm_card_id: null, status: 'new_lead' })).toBe(
      false
    );
  });

  it('detalhe é funil, estágio e responsável', () => {
    const lead = { crm_card_id: 555, crm_presence: presence };

    expect(crmPresenceDetail(lead, 'sem responsável')).toBe(
      'Vendas, Novo, Ana Souza'
    );
  });

  it('card sem responsável diz que não tem responsável', () => {
    const lead = {
      crm_card_id: 555,
      crm_presence: { ...presence, owner_name: null },
    };

    expect(crmPresenceDetail(lead, 'sem responsável')).toBe(
      'Vendas, Novo, sem responsável'
    );
  });

  it('card recém-criado, sem o detalhe ainda, e lead fora do CRM não têm detalhe', () => {
    expect(crmPresenceDetail({ crm_card_id: 555 }, 'x')).toBe('');
    expect(
      crmPresenceDetail({ crm_card_id: null, crm_presence: presence }, 'x')
    ).toBe('');
  });
});
