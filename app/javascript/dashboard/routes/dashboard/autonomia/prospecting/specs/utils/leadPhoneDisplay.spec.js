// Telefone exibido no card, como no Orth (search-lead-phone.ts
// getSearchLeadPhonePresentation): o número canônico formatado, dando
// preferência ao número do WhatsApp verificado; sem contrato, o texto cru.
import { leadPhoneDisplay } from '../../utils/leadPhone';

describe('leadPhone · telefone exibido no card', () => {
  it('formata o número nacional no padrão internacional', () => {
    expect(leadPhoneDisplay({ phone: '(41) 99999-0001' })).toBe(
      '+55 41 99999 0001'
    );
  });

  it('usa a região da busca para o número sem DDI', () => {
    expect(leadPhoneDisplay({ phone: '912 345 678' }, 'PT')).toBe(
      '+351 912 345 678'
    );
  });

  it('prefere o número verificado do WhatsApp', () => {
    expect(
      leadPhoneDisplay({
        phone: '4133330002',
        whatsapp_phone: '+5541999990001',
      })
    ).toBe('+55 41 99999 0001');
  });

  it('número que não fecha o contrato aparece como veio', () => {
    expect(leadPhoneDisplay({ phone: '123' })).toBe('123');
  });

  it('sem número não mostra nada', () => {
    expect(leadPhoneDisplay({ phone: null })).toBe('');
  });
});
