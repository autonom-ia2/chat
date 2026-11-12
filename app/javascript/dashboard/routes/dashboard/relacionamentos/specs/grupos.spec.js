import {
  DIA_EM_MS,
  GRUPOS_DE_EMPRESAS,
  GRUPOS_DE_PESSOAS,
  LIMITE_FALOU_HA_POUCO_DIAS,
  LIMITE_SUMIU_DIAS,
  empresaPertenceAoGrupo,
  pertenceAoGrupo,
} from '../fonte/grupos';

// Os grupos da lista de Relacionamentos (#2894): cada um responde a uma pergunta
// da pessoa ("quem sumiu?"), não a um filtro. Aqui só a regra, sem tela.
const AGORA = 1_700_000_000_000;
const UM_SEGUNDO = 1000;

const segundos = ms => Math.floor(ms / 1000);
const haDias = (dias, extraMs = 0) =>
  segundos(AGORA - dias * DIA_EM_MS - extraMs);

const pessoa = (extra = {}) => ({
  id: 1,
  contact_type: 'lead',
  last_activity_at: haDias(5),
  opted_out_at: null,
  ...extra,
});

const gruposDe = p =>
  GRUPOS_DE_PESSOAS.filter(g => pertenceAoGrupo(p, g.id, AGORA)).map(g => g.id);

describe('grupos de pessoas', () => {
  it('lista os grupos na ordem da tela', () => {
    expect(GRUPOS_DE_PESSOAS.map(g => g.id)).toEqual([
      'todos',
      'clientes',
      'falou_ha_pouco',
      'sumiu_1_a_3_meses',
      'sumiu_mais_de_3_meses',
      'nunca_conversou',
      'nao_quer_mensagens',
    ]);
  });

  it('dá a cada grupo a chave do nome e da explicação', () => {
    GRUPOS_DE_PESSOAS.forEach(g => {
      expect(typeof g.nome).toBe('string');
      expect(typeof g.explicacao).toBe('string');
      expect(g.nome.startsWith('RELACIONAMENTOS.GRUPOS.')).toBe(true);
      expect(g.explicacao.startsWith('RELACIONAMENTOS.GRUPOS.')).toBe(true);
    });
  });

  it('usa limites de 30 e 90 dias', () => {
    expect(LIMITE_FALOU_HA_POUCO_DIAS).toBe(30);
    expect(LIMITE_SUMIU_DIAS).toBe(90);
  });

  it('põe todo mundo em "todos"', () => {
    expect(pertenceAoGrupo(pessoa(), 'todos', AGORA)).toBe(true);
    expect(
      pertenceAoGrupo(pessoa({ last_activity_at: null }), 'todos', AGORA)
    ).toBe(true);
  });

  it('só põe em "clientes" quem é cliente', () => {
    expect(
      pertenceAoGrupo(pessoa({ contact_type: 'customer' }), 'clientes', AGORA)
    ).toBe(true);
    expect(
      pertenceAoGrupo(pessoa({ contact_type: 'lead' }), 'clientes', AGORA)
    ).toBe(false);
  });

  it('só põe em "não quer mensagens" quem pediu para parar', () => {
    expect(
      pertenceAoGrupo(
        pessoa({ opted_out_at: 1_699_000_000 }),
        'nao_quer_mensagens',
        AGORA
      )
    ).toBe(true);
    expect(
      pertenceAoGrupo(
        pessoa({ opted_out_at: null }),
        'nao_quer_mensagens',
        AGORA
      )
    ).toBe(false);
    expect(
      pertenceAoGrupo(
        pessoa({ opted_out_at: undefined }),
        'nao_quer_mensagens',
        AGORA
      )
    ).toBe(false);
  });

  describe('borda de 30 dias', () => {
    it('conta 30 dias exatos ainda como "falou há pouco"', () => {
      expect(gruposDe(pessoa({ last_activity_at: haDias(30) }))).toContain(
        'falou_ha_pouco'
      );
      expect(gruposDe(pessoa({ last_activity_at: haDias(30) }))).not.toContain(
        'sumiu_1_a_3_meses'
      );
    });

    it('passa para "sumiu há 1 a 3 meses" um segundo depois', () => {
      const p = pessoa({ last_activity_at: haDias(30, UM_SEGUNDO) });
      expect(gruposDe(p)).toContain('sumiu_1_a_3_meses');
      expect(gruposDe(p)).not.toContain('falou_ha_pouco');
    });

    it('trata conversa de hoje como "falou há pouco"', () => {
      expect(gruposDe(pessoa({ last_activity_at: haDias(0) }))).toContain(
        'falou_ha_pouco'
      );
    });
  });

  describe('borda de 90 dias', () => {
    it('conta 90 dias exatos ainda como "sumiu há 1 a 3 meses"', () => {
      const p = pessoa({ last_activity_at: haDias(90) });
      expect(gruposDe(p)).toContain('sumiu_1_a_3_meses');
      expect(gruposDe(p)).not.toContain('sumiu_mais_de_3_meses');
    });

    it('passa para "sumiu há mais de 3 meses" um segundo depois', () => {
      const p = pessoa({ last_activity_at: haDias(90, UM_SEGUNDO) });
      expect(gruposDe(p)).toContain('sumiu_mais_de_3_meses');
      expect(gruposDe(p)).not.toContain('sumiu_1_a_3_meses');
    });

    it('mantém quem some há um ano em "mais de 3 meses"', () => {
      expect(gruposDe(pessoa({ last_activity_at: haDias(365) }))).toContain(
        'sumiu_mais_de_3_meses'
      );
    });
  });

  describe('sem data de conversa', () => {
    it.each([null, undefined])(
      'põe %s em "nunca conversou" e em nenhum outro grupo de conversa',
      nulo => {
        const grupos = gruposDe(pessoa({ last_activity_at: nulo }));
        expect(grupos).toContain('nunca_conversou');
        expect(grupos).not.toContain('falou_ha_pouco');
        expect(grupos).not.toContain('sumiu_1_a_3_meses');
        expect(grupos).not.toContain('sumiu_mais_de_3_meses');
      }
    );

    it('não põe em "nunca conversou" quem já conversou', () => {
      expect(
        pertenceAoGrupo(
          pessoa({ last_activity_at: haDias(1) }),
          'nunca_conversou',
          AGORA
        )
      ).toBe(false);
    });
  });

  it('põe cada pessoa em exatamente um dos quatro grupos de conversa', () => {
    const dias = [0, 1, 29, 30, 31, 89, 90, 91, 400];
    const todas = [null, ...dias.map(d => haDias(d))];
    todas.forEach(ultima => {
      const conversa = gruposDe(pessoa({ last_activity_at: ultima })).filter(
        id =>
          [
            'falou_ha_pouco',
            'sumiu_1_a_3_meses',
            'sumiu_mais_de_3_meses',
            'nunca_conversou',
          ].includes(id)
      );
      expect(conversa).toHaveLength(1);
    });
  });

  it('não pertence a grupo que não existe', () => {
    expect(pertenceAoGrupo(pessoa(), 'inventado', AGORA)).toBe(false);
  });
});

describe('grupos de empresas', () => {
  const empresa = (extra = {}) => ({
    id: 1,
    contacts_count: 3,
    customers_count: 0,
    last_activity_at: haDias(10),
    ...extra,
  });
  const gruposDaEmpresa = e =>
    GRUPOS_DE_EMPRESAS.filter(g => empresaPertenceAoGrupo(e, g.id, AGORA)).map(
      g => g.id
    );

  it('lista os grupos na ordem da tela', () => {
    expect(GRUPOS_DE_EMPRESAS.map(g => g.id)).toEqual([
      'todas',
      'com_clientes',
      'sem_pessoas',
      'sem_conversa_3_meses',
    ]);
  });

  it('dá a cada grupo a chave do nome e da explicação', () => {
    GRUPOS_DE_EMPRESAS.forEach(g => {
      expect(g.nome.startsWith('RELACIONAMENTOS.GRUPOS.')).toBe(true);
      expect(g.explicacao.startsWith('RELACIONAMENTOS.GRUPOS.')).toBe(true);
    });
  });

  it('põe toda empresa em "todas"', () => {
    expect(gruposDaEmpresa(empresa())).toContain('todas');
  });

  it('põe em "com clientes" a empresa com ao menos um cliente', () => {
    expect(gruposDaEmpresa(empresa({ customers_count: 1 }))).toContain(
      'com_clientes'
    );
    expect(gruposDaEmpresa(empresa({ customers_count: 0 }))).not.toContain(
      'com_clientes'
    );
  });

  it('põe em "sem pessoas" a empresa sem ninguém', () => {
    expect(gruposDaEmpresa(empresa({ contacts_count: 0 }))).toContain(
      'sem_pessoas'
    );
    expect(gruposDaEmpresa(empresa({ contacts_count: 1 }))).not.toContain(
      'sem_pessoas'
    );
  });

  it('respeita a borda de 90 dias em "sem conversa há 3 meses"', () => {
    expect(
      gruposDaEmpresa(empresa({ last_activity_at: haDias(90) }))
    ).not.toContain('sem_conversa_3_meses');
    expect(
      gruposDaEmpresa(empresa({ last_activity_at: haDias(90, UM_SEGUNDO) }))
    ).toContain('sem_conversa_3_meses');
  });

  it('põe empresa que nunca conversou em "sem conversa há 3 meses"', () => {
    expect(gruposDaEmpresa(empresa({ last_activity_at: null }))).toContain(
      'sem_conversa_3_meses'
    );
  });

  it('não pertence a grupo que não existe', () => {
    expect(empresaPertenceAoGrupo(empresa(), 'inventado', AGORA)).toBe(false);
  });
});
