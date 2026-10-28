import {
  abrirListaNovaSeLigada,
  voltarParaListaAtualSeDesligada,
} from '../listaPelaFlag';
import funcoesDaEquipeRoutes from '../funcoesDaEquipe.routes';
import customRoleRoutes from '../../customRoles/customRole.routes';

// #2308: a flag funcoes_guiadas escolhe a lista. Ligada, Funções pelo menu abre a nova; desligada, tudo como hoje.
const conta = vi.hoisted(() => ({ atual: null }));
vi.mock('dashboard/routes/dashboard/autonomia/contaDaRota', () => ({
  contaDaRota: async () => conta.atual,
}));

const para = { params: { accountId: '1' } };

describe('Funções da equipe: qual lista abre', () => {
  it('com a flag ligada, a lista de hoje leva à nova e a nova abre', async () => {
    conta.atual = { id: 1, features: { funcoes_guiadas: true } };

    expect(await abrirListaNovaSeLigada(para)).toEqual({
      name: 'funcoes_equipe_list',
      params: para.params,
    });
    expect(await voltarParaListaAtualSeDesligada(para)).toBe(true);
  });

  it('com a flag desligada, a lista de hoje abre e a nova volta para ela', async () => {
    conta.atual = { id: 1, features: { funcoes_guiadas: false } };

    expect(await abrirListaNovaSeLigada(para)).toBe(true);
    expect(await voltarParaListaAtualSeDesligada(para)).toEqual({
      name: 'custom_roles_list',
      params: para.params,
    });
  });

  it('sem conta carregada, fica a tela de hoje', async () => {
    conta.atual = null;

    expect(await abrirListaNovaSeLigada(para)).toBe(true);
  });

  it('as duas listas usam os guardas e o mesmo acesso', () => {
    const [nova] = funcoesDaEquipeRoutes.routes;
    const atual = customRoleRoutes.routes[0].children.find(
      rota => rota.name === 'custom_roles_list'
    );

    expect(nova.name).toBe('funcoes_equipe_list');
    expect(nova.beforeEnter).toBe(voltarParaListaAtualSeDesligada);
    expect(atual.beforeEnter).toBe(abrirListaNovaSeLigada);
    expect(nova.meta).toEqual(atual.meta);
  });
});
