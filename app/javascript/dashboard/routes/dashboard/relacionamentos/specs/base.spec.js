import { ETIQUETAS } from '../demo/acoesDaLista';
import { empresaPorId, empresas, pessoaPorId, pessoas } from '../demo/base';
import { DIA_EM_MS, GRUPOS_DE_PESSOAS, pertenceAoGrupo } from '../fonte/grupos';

// A base fictícia (#2894): 280 pessoas e 38 empresas inventadas, sempre iguais,
// com a distribuição que a especificação do Bloco A pede.
const AGORA = 1_700_000_000_000;
const contar = (lista, regra) => lista.filter(regra).length;
const doGrupo = id => pessoas(AGORA).filter(p => pertenceAoGrupo(p, id, AGORA));

describe('pessoas', () => {
  it('traz 280 pessoas', () => {
    expect(pessoas(AGORA)).toHaveLength(280);
  });

  it('é determinística: a mesma lista a cada carga', () => {
    expect(pessoas(AGORA)).toEqual(pessoas(AGORA));
    expect(empresas(AGORA)).toEqual(empresas(AGORA));
  });

  it('não repete id, nome nem telefone', () => {
    const lista = pessoas(AGORA);
    const unicos = campo =>
      new Set(lista.map(p => p[campo]).filter(Boolean)).size;
    expect(unicos('id')).toBe(280);
    expect(unicos('name')).toBe(280);
    expect(unicos('phone_number')).toBe(276);
  });

  it.each([
    ['clientes', 120],
    ['falou_ha_pouco', 96],
    ['sumiu_1_a_3_meses', 42],
    ['sumiu_mais_de_3_meses', 71],
    ['nunca_conversou', 71],
    ['nao_quer_mensagens', 9],
    ['todos', 280],
  ])('distribui %s em %i pessoas', (grupo, total) => {
    expect(doGrupo(grupo)).toHaveLength(total);
  });

  it('tem 4 pessoas sem telefone', () => {
    expect(contar(pessoas(AGORA), p => !p.phone_number)).toBe(4);
  });

  it('põe cada pessoa em um só dos quatro grupos de conversa', () => {
    const soma = [
      'falou_ha_pouco',
      'sumiu_1_a_3_meses',
      'sumiu_mais_de_3_meses',
      'nunca_conversou',
    ]
      .map(id => doGrupo(id).length)
      .reduce((a, b) => a + b, 0);
    expect(soma).toBe(280);
  });

  it('cruza cliente e "não quer mensagens" com os grupos de conversa', () => {
    const clientesQueSumiram = doGrupo('clientes').filter(p =>
      pertenceAoGrupo(p, 'sumiu_mais_de_3_meses', AGORA)
    );
    expect(clientesQueSumiram.length).toBeGreaterThan(0);
    expect(doGrupo('nao_quer_mensagens').every(p => p.opt_out_source)).toBe(
      true
    );
  });

  it('usa datas relativas ao agora, para os grupos não envelhecerem', () => {
    const depois = AGORA + 400 * DIA_EM_MS;
    const falouEmCadaMomento = pessoas(depois).filter(p =>
      pertenceAoGrupo(p, 'falou_ha_pouco', depois)
    );
    expect(falouEmCadaMomento).toHaveLength(96);
  });

  describe('dados fictícios', () => {
    it('usa telefone do bloco fictício, terminando em número baixo', () => {
      pessoas(AGORA)
        .filter(p => p.phone_number)
        .forEach(p => {
          expect(p.phone_number.startsWith('+55119')).toBe(true);
          expect(p.phone_number).toHaveLength(14);
          expect(p.phone_number.slice(-4, -2)).toBe('00');
        });
    });

    it('usa e-mail de exemplo', () => {
      pessoas(AGORA).forEach(p => {
        expect(p.email.endsWith('@exemplo.com.br')).toBe(true);
      });
    });

    it('só traz CPF de verdade inválido, só com dígitos', () => {
      const cpfs = pessoas(AGORA)
        .map(p => p.custom_attributes.cpf)
        .filter(Boolean);
      expect(cpfs.length).toBeGreaterThan(0);
      cpfs.forEach(cpf => {
        expect(cpf).toHaveLength(11);
        expect([...cpf].every(c => c >= '0' && c <= '9')).toBe(true);
      });
    });
  });

  describe('formato da API de contatos', () => {
    it('traz os campos que a API devolve hoje e os dois da API nova', () => {
      const campos = [
        'id',
        'name',
        'email',
        'phone_number',
        'thumbnail',
        'contact_type',
        'customer_since',
        'last_activity_at',
        'created_at',
        'additional_attributes',
        'custom_attributes',
        'labels',
        'company_id',
        'opted_out_at',
        'opt_out_source',
      ];
      pessoas(AGORA).forEach(p => {
        campos.forEach(campo => expect(p).toHaveProperty(campo));
        expect(p.additional_attributes).toHaveProperty('city');
        expect(p.additional_attributes).toHaveProperty('company_name');
        expect(Array.isArray(p.labels)).toBe(true);
      });
    });

    it('marca cliente com contact_type e customer_since', () => {
      pessoas(AGORA).forEach(p => {
        const cliente = p.contact_type === 'customer';
        expect(Boolean(p.customer_since)).toBe(cliente);
      });
    });

    it('guarda as datas em segundos, como a API', () => {
      pessoas(AGORA)
        .filter(p => p.last_activity_at !== null)
        .forEach(p => {
          expect(Number.isInteger(p.last_activity_at)).toBe(true);
          expect(p.last_activity_at).toBeLessThanOrEqual(AGORA / 1000);
        });
    });
  });

  it('acha pessoa e empresa pelo id', () => {
    const primeira = pessoas(AGORA)[0];
    expect(pessoaPorId(primeira.id, AGORA)).toEqual(primeira);
    expect(pessoaPorId(-1, AGORA)).toBeNull();
    const empresa = empresas(AGORA)[0];
    expect(empresaPorId(empresa.id, AGORA)).toEqual(empresa);
    expect(empresaPorId(-1, AGORA)).toBeNull();
  });

  it('cobre todos os grupos de pessoas definidos', () => {
    GRUPOS_DE_PESSOAS.forEach(g =>
      expect(doGrupo(g.id).length).toBeGreaterThan(0)
    );
  });
});

describe('empresas', () => {
  it('traz 38 empresas, com id e nome únicos', () => {
    const lista = empresas(AGORA);
    expect(lista).toHaveLength(38);
    expect(new Set(lista.map(e => e.id)).size).toBe(38);
    expect(new Set(lista.map(e => e.name)).size).toBe(38);
  });

  it('traz os campos de empresa', () => {
    empresas(AGORA).forEach(e => {
      [
        'id',
        'name',
        'domain',
        'cnpj',
        'contacts_count',
        'last_activity_at',
        'customers_count',
      ].forEach(campo => expect(e).toHaveProperty(campo));
      expect(e.cnpj).toHaveLength(14);
    });
  });

  it('tem 14 empresas com cliente e 5 sem pessoas', () => {
    const lista = empresas(AGORA);
    expect(contar(lista, e => e.customers_count > 0)).toBe(14);
    expect(contar(lista, e => e.contacts_count === 0)).toBe(5);
  });

  it('bate contacts_count e customers_count com as pessoas da empresa', () => {
    const gente = pessoas(AGORA);
    empresas(AGORA).forEach(e => {
      const dela = gente.filter(p => p.company_id === e.id);
      expect(e.contacts_count).toBe(dela.length);
      expect(e.customers_count).toBe(
        contar(dela, p => p.contact_type === 'customer')
      );
    });
  });

  it('usa a última conversa mais recente das pessoas da empresa', () => {
    const gente = pessoas(AGORA);
    empresas(AGORA).forEach(e => {
      const datas = gente
        .filter(p => p.company_id === e.id && p.last_activity_at)
        .map(p => p.last_activity_at);
      expect(e.last_activity_at).toBe(datas.length ? Math.max(...datas) : null);
    });
  });

  it('põe o nome da empresa nas pessoas dela', () => {
    const porId = Object.fromEntries(empresas(AGORA).map(e => [e.id, e.name]));
    pessoas(AGORA)
      .filter(p => p.company_id)
      .forEach(p =>
        expect(p.additional_attributes.company_name).toBe(porId[p.company_id])
      );
  });
});

describe('etiquetas fictícias', () => {
  it('aparecem com acento, como a pessoa as escreveria', () => {
    const usadas = new Set(pessoas(AGORA).flatMap(p => p.labels));
    expect(usadas.has('indicação')).toBe(true);
    expect(usadas.has('indicacao')).toBe(false);
    expect(ETIQUETAS).toContain('indicação');
    expect(ETIQUETAS).not.toContain('indicacao');
  });
});

describe('pessoa bloqueada na demonstração', () => {
  it('há uma, no grupo "Sumiu há 1 a 3 meses", com telefone e sem ter pedido para parar', () => {
    const bloqueadas = pessoas(AGORA).filter(p => p.blocked);
    expect(bloqueadas).toHaveLength(1);
    const [pessoa] = bloqueadas;
    expect(pertenceAoGrupo(pessoa, 'sumiu_1_a_3_meses', AGORA)).toBe(true);
    expect(pessoa.phone_number).toBeTruthy();
    expect(pessoa.opted_out_at).toBeNull();
  });
});
