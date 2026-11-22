import { rotaDaEmpresa, rotaDaPessoa } from '../useFichaDoContato';

// #3130 — com o menu novo de Relacionamentos, todo link leva à ficha nova.
describe('rotaDaPessoa e rotaDaEmpresa', () => {
  it('levam à ficha nova quando a conta tem o menu novo', () => {
    expect(rotaDaPessoa(1, 42, true)).toEqual({
      name: 'relacionamentos_pessoa',
      params: { accountId: 1, contactId: 42 },
    });
    expect(rotaDaEmpresa(1, 7, true)).toEqual({
      name: 'relacionamentos_empresa',
      params: { accountId: 1, companyId: 7 },
    });
  });

  it('levam à tela antiga só quando a conta não tem o menu novo', () => {
    expect(rotaDaPessoa(1, 42, false).name).toBe('contacts_edit');
    expect(rotaDaEmpresa(1, 7, false).name).toBe('companies_dashboard_show');
  });
});
