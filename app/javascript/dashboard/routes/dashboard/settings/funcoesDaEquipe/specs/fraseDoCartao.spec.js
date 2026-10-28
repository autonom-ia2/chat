import { PRESETS } from '../../customRoles/permissionMatrix';
import { cuidadosDaFuncao, fraseDoCartao } from '../fraseDoCartao';

// #2308: a frase curta do cartão lê só o nível das três áreas fixas; o selo, o que pede cuidado.
describe('fraseDoCartao', () => {
  it('Atendente: próprias e novas, mexe nas vendas, só olha os contatos', () => {
    expect(fraseDoCartao(PRESETS.AGENT())).toEqual({
      destaque: 'PROPRIAS_E_NOVAS',
      resto: ['VENDAS_MEXE', 'CONTATOS_SO_OLHA'],
    });
  });

  it('Marketing: não atende conversas, só olha as vendas, mexe nos contatos', () => {
    expect(fraseDoCartao(PRESETS.MARKETING())).toEqual({
      destaque: 'NAO_ATENDE',
      resto: ['VENDAS_SO_OLHA', 'CONTATOS_MEXE'],
    });
  });

  it('área sem acesso não entra na frase; crm_admin cuida de tudo nas vendas', () => {
    expect(fraseDoCartao(['conversation_manage', 'crm_admin'])).toEqual({
      destaque: 'TODAS',
      resto: ['VENDAS_TUDO'],
    });
  });
});

describe('cuidadosDaFuncao', () => {
  it('Vendedor pronto não tem selo', () => {
    expect(cuidadosDaFuncao(PRESETS.SDR())).toEqual([]);
  });

  it('com crm_admin, as seis que ele inclui ficam dentro dele', () => {
    expect(
      cuidadosDaFuncao([
        'crm_admin',
        'crm_export',
        'crm_metas_manage',
        'contact_export',
      ])
    ).toEqual(['crm_admin', 'contact_export']);
  });
});
