import {
  abrirNovaSeLigada,
  voltarParaAtualSeDesligada,
} from '../listaPelaFlag';
import funcoesDaEquipeRoutes from '../funcoesDaEquipe.routes';
import customRoleRoutes from '../../customRoles/customRole.routes';

// #2308: a flag funcoes_guiadas escolhe a tela. Ligada, a lista, criar, alterar e duplicar de hoje levam às novas;
// desligada, as novas voltam para as de hoje.
const conta = vi.hoisted(() => ({ atual: null }));
vi.mock('dashboard/routes/dashboard/autonomia/contaDaRota', () => ({
  contaDaRota: async () => conta.atual,
}));

const params = { accountId: '1' };
const ligada = () => {
  conta.atual = { id: 1, features: { funcoes_guiadas: true } };
};
const desligada = () => {
  conta.atual = { id: 1, features: { funcoes_guiadas: false } };
};

describe('Funções da equipe: qual tela abre', () => {
  it('com a flag ligada, a lista de hoje leva à nova e a nova abre', async () => {
    ligada();
    const lista = { name: 'custom_roles_list', params };

    expect(await abrirNovaSeLigada(lista)).toEqual({
      name: 'funcoes_equipe_list',
      params,
    });
    expect(
      await voltarParaAtualSeDesligada({ name: 'funcoes_equipe_list', params })
    ).toBe(true);
  });

  it('com a flag ligada, criar, alterar e duplicar de hoje levam aos guiados', async () => {
    ligada();
    const comFuncao = { ...params, roleId: '4' };

    expect(
      await abrirNovaSeLigada({ name: 'custom_roles_new', params })
    ).toEqual({ name: 'funcoes_equipe_new', params });
    expect(
      await abrirNovaSeLigada({ name: 'custom_roles_edit', params: comFuncao })
    ).toEqual({ name: 'funcoes_equipe_edit', params: comFuncao });
    expect(
      await abrirNovaSeLigada({
        name: 'custom_roles_new',
        params,
        query: { duplicate: '4' },
      })
    ).toEqual({ name: 'funcoes_equipe_duplicate', params: comFuncao });
  });

  it('com a flag desligada, as novas voltam para as de hoje', async () => {
    desligada();
    const comFuncao = { ...params, roleId: '4' };

    expect(await abrirNovaSeLigada({ name: 'custom_roles_list', params })).toBe(
      true
    );
    expect(
      await voltarParaAtualSeDesligada({ name: 'funcoes_equipe_list', params })
    ).toEqual({ name: 'custom_roles_list', params });
    expect(
      await voltarParaAtualSeDesligada({ name: 'funcoes_equipe_new', params })
    ).toEqual({ name: 'custom_roles_new', params });
    expect(
      await voltarParaAtualSeDesligada({
        name: 'funcoes_equipe_edit',
        params: comFuncao,
      })
    ).toEqual({ name: 'custom_roles_edit', params: comFuncao });
    expect(
      await voltarParaAtualSeDesligada({
        name: 'funcoes_equipe_duplicate',
        params: comFuncao,
      })
    ).toEqual({
      name: 'custom_roles_new',
      params,
      query: { duplicate: '4' },
    });
  });

  it('sem conta carregada, fica a tela de hoje', async () => {
    conta.atual = null;

    expect(await abrirNovaSeLigada({ name: 'custom_roles_new', params })).toBe(
      true
    );
  });

  it('as rotas novas usam o guarda e o mesmo acesso das de hoje', () => {
    const atuais = customRoleRoutes.routes[0].children.filter(
      rota => rota.name
    );
    const novas = funcoesDaEquipeRoutes.routes;

    expect(novas.map(rota => rota.name)).toEqual([
      'funcoes_equipe_list',
      'funcoes_equipe_new',
      'funcoes_equipe_edit',
      'funcoes_equipe_duplicate',
    ]);
    novas.forEach(rota => {
      expect(rota.beforeEnter).toBe(voltarParaAtualSeDesligada);
      expect(rota.meta).toEqual(atuais[0].meta);
    });
    atuais.forEach(rota => expect(rota.beforeEnter).toBe(abrirNovaSeLigada));
  });
});
