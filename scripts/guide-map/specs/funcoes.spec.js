import { conferir, lerChaves } from '../funcoes.mjs';

const chaves = ['campaign_view', 'campaign_manage', 'crm_view'];
const rota = (nome, papeis) => ({ nome, papeis });

describe('funcoes (#1157)', () => {
  it('lê as chaves do modelo, uma por linha', () => {
    const rubi =
      'class CustomRole\n  PERMISSIONS = %w[\n    crm_view\n    campaign_view\n  ].freeze\nend';
    expect(lerChaves(rubi)).toEqual(['crm_view', 'campaign_view']);
  });

  it('aceita rota com chave de função e rota declarada só administrador', () => {
    const resultado = conferir({
      chaves,
      excecoes: { _leia: 'x', conta: 'Conta. Nunca por função.' },
      rotas: [
        rota('campanhas', ['administrator', 'campaign_view']),
        rota('perfil', ['administrator', 'agent', 'custom_role']),
        rota('conta', ['administrator']),
        rota('redirecionamento', null),
      ],
    });

    expect(resultado).toEqual({ semDecisao: [], sobrando: [] });
  });

  it('reprova tela nova só de administrador ou só de agente, sem decisão', () => {
    const { semDecisao } = conferir({
      chaves,
      excecoes: {},
      rotas: [
        rota('anuncios', ['administrator']),
        rota('midia', ['administrator', 'agent']),
      ],
    });

    expect(semDecisao).toEqual(['anuncios', 'midia']);
  });

  it('entrada com _ no fim cobre o prefixo', () => {
    const { semDecisao } = conferir({
      chaves,
      excecoes: { times_: 'Times.' },
      rotas: [
        rota('times_lista', ['administrator']),
        rota('times_novo', ['administrator']),
      ],
    });

    expect(semDecisao).toEqual([]);
  });

  it('cobra a saída da lista quando a tela passa a abrir para função ou some', () => {
    const { sobrando } = conferir({
      chaves,
      excecoes: { anuncios: 'Lote 1.', antiga_: 'Removida.' },
      rotas: [rota('anuncios', ['administrator', 'campaign_view'])],
    });

    expect(sobrando).toEqual(['anuncios', 'antiga_']);
  });
});
