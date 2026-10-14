import { fusoDaConta, rotuloDoFuso } from '../fusoDaConta';

// #1456: o fuso como Configurações da conta o mostra (a lista de fusos do #954).
describe('rotuloDoFuso', () => {
  it('mostra o fuso como a lista de Configurações da conta', () => {
    expect(rotuloDoFuso('America/Sao_Paulo')).toBe('America/Sao Paulo');
    expect(rotuloDoFuso('America/Porto_Velho')).toBe('America/Porto Velho');
    expect(rotuloDoFuso('UTC')).toBe('UTC');
  });

  it('sem fuso, vazio', () => {
    expect(rotuloDoFuso(undefined)).toBe('');
  });
});

// #1568: o calendário usa o fuso da conta; sem ele, o padrão do CRM; nunca o do navegador.
describe('fusoDaConta', () => {
  afterEach(() => {
    delete window.globalConfig;
  });

  it('usa o fuso escolhido em Configurações', () => {
    expect(
      fusoDaConta({ custom_attributes: { timezone: 'America/Cuiaba' } })
    ).toBe('America/Cuiaba');
    expect(
      fusoDaConta({ settings: { reporting_timezone: 'America/Manaus' } })
    ).toBe('America/Manaus');
  });

  it('sem fuso na conta, usa o padrão do CRM, não o do navegador', () => {
    window.globalConfig = { CRM_DEFAULT_TIMEZONE: 'America/Belem' };
    expect(fusoDaConta({})).toBe('America/Belem');
  });

  it('ignora fuso inválido', () => {
    window.globalConfig = { CRM_DEFAULT_TIMEZONE: 'America/Recife' };
    expect(fusoDaConta({ custom_attributes: { timezone: 'Lua/Base' } })).toBe(
      'America/Recife'
    );
  });
});
