import { buildCrmCardIdentity, crmCardIdentityLabel } from './cardIdentity.js';

describe('CRM card identity', () => {
  it('uses the opportunity company before the shared contact company', () => {
    const card = {
      title: 'Implantação do atendimento',
      company: { id: 7, name: 'Norte Logística' },
      contact: {
        name: 'Mariana Costa',
        company: { id: 99, name: 'Empresa antiga' },
      },
    };
    const identity = buildCrmCardIdentity(card, 'Card avulso');

    expect(identity).toEqual({
      company: 'Norte Logística',
      person: 'Mariana Costa',
      business: 'Implantação do atendimento',
      main: 'Norte Logística',
    });
    expect(crmCardIdentityLabel(card, 'Card avulso')).toBe(
      'Norte Logística Implantação do atendimento'
    );
  });

  it('keeps a person as the main identity for B2C opportunities', () => {
    expect(
      buildCrmCardIdentity(
        { title: 'Plano anual', contact: { name: 'Ana Clara Souza' } },
        'Card avulso'
      )
    ).toEqual({
      company: '',
      person: '',
      business: 'Plano anual',
      main: 'Ana Clara Souza',
    });
  });

  it('uses the business title as the only honest identity without a contact', () => {
    expect(
      buildCrmCardIdentity(
        { title: 'Indicação recebida na feira', contact: null },
        'Card avulso'
      )
    ).toEqual({
      company: '',
      person: '',
      business: '',
      main: 'Indicação recebida na feira',
    });
  });

  it('does not repeat a phone number as a second business line', () => {
    expect(
      buildCrmCardIdentity(
        {
          title: '+55 11 90000-0010',
          contact: { phone_number: '+55 11 90000-0010' },
        },
        'Card avulso'
      ).business
    ).toBe('');
  });

  it('shows a phone-only contact name readable, only on screen (#2255)', () => {
    const contact = { name: '5511955554444', phone_number: '+5511955554444' };
    expect(
      buildCrmCardIdentity({ title: '+5511955554444', contact }, 'Card avulso')
    ).toEqual({
      company: '',
      person: '',
      business: '',
      main: '+55 11 95555-4444',
    });
    expect(contact.name).toBe('5511955554444');
    expect(
      buildCrmCardIdentity({ contact: { name: 'Joana' } }, 'Card avulso').main
    ).toBe('Joana');
  });

  it('does not repeat the raw phone-only contact name as the business line (#2255)', () => {
    expect(
      buildCrmCardIdentity(
        {
          title: '5511955554444',
          contact: { name: '5511955554444', phone_number: '+5511955554444' },
        },
        'Card avulso'
      )
    ).toEqual({
      company: '',
      person: '',
      business: '',
      main: '+55 11 95555-4444',
    });
  });
});
