import {
  COMO_DO_TIPO,
  JUNTAR,
  MODELOS,
  OPERADORES,
  TIPOS,
  catalogoDeInformacoes,
  comComo,
  comInformacao,
  comosDa,
  condicoesProntas,
  erroDaCondicao,
  novaCondicao,
  paraOServidor,
  pedeValor,
  rotuloDoComo,
  temUmComoSo,
} from '../../lista/informacoes';
import { FILTROS_VAZIOS, contarFiltros } from '../../lista/filtros';
import { paramsDoPedido } from '../../fonte/listaFonte';

// #3168 — o catálogo de "Por outra informação" e a conta de cada linha.
const t = (chave, valores) =>
  valores ? `${chave}:${JSON.stringify(valores)}` : chave;
const catalogo = (extra = {}) =>
  catalogoDeInformacoes({ t, idioma: 'pt-BR', ...extra });

const linha = (dados = {}) => ({
  ...novaCondicao(1),
  chave: 'city',
  tipo: TIPOS.TEXTO,
  modelo: MODELOS.PADRAO,
  como: OPERADORES.TEM,
  valor: 'Campinas',
  ...dados,
});

describe('o "como" de cada tipo', () => {
  it('segue a tabela da fatia 6', () => {
    const { TEM, NAO_TEM, IGUAL, DIFERENTE, DEPOIS, ANTES, HA_MAIS_DE_DIAS } =
      OPERADORES;
    expect(COMO_DO_TIPO[TIPOS.TEXTO]).toEqual([TEM, NAO_TEM, IGUAL, DIFERENTE]);
    [TIPOS.IGUAL, TIPOS.LISTA, TIPOS.NUMERO, TIPOS.LINK].forEach(tipo =>
      expect(COMO_DO_TIPO[tipo]).toEqual([IGUAL, DIFERENTE])
    );
    expect(COMO_DO_TIPO[TIPOS.SIM_NAO]).toEqual([IGUAL]);
    expect(COMO_DO_TIPO[TIPOS.DATA]).toEqual([DEPOIS, ANTES, HA_MAIS_DE_DIAS]);
    expect(COMO_DO_TIPO[TIPOS.DATA_DA_CONTA]).toEqual([
      DEPOIS,
      ANTES,
      HA_MAIS_DE_DIAS,
      OPERADORES.PREENCHIDO,
      OPERADORES.VAZIO,
    ]);
  });

  it('no texto diz "é igual a"; nos outros, só "é"', () => {
    expect(rotuloDoComo(TIPOS.TEXTO, OPERADORES.IGUAL)).toBe('IGUAL_A');
    expect(rotuloDoComo(TIPOS.TEXTO, OPERADORES.DIFERENTE)).toBe(
      'DIFERENTE_DE'
    );
    expect(rotuloDoComo(TIPOS.LISTA, OPERADORES.IGUAL)).toBe('E');
    expect(rotuloDoComo(TIPOS.LISTA, OPERADORES.DIFERENTE)).toBe('NAO_E');
    expect(rotuloDoComo(TIPOS.DATA, OPERADORES.HA_MAIS_DE_DIAS)).toBe(
      'HA_MAIS_DE_DIAS'
    );
  });

  it('"está preenchido" e "está vazio" não pedem valor', () => {
    expect(pedeValor(OPERADORES.PREENCHIDO)).toBe(false);
    expect(pedeValor(OPERADORES.VAZIO)).toBe(false);
    expect(pedeValor(OPERADORES.TEM)).toBe(true);
  });
});

describe('catalogoDeInformacoes', () => {
  it('traz as informações da pessoa com as chaves do filtro antigo', () => {
    const chaves = catalogo().daPessoa.map(({ chave }) => chave);
    expect(chaves).toEqual([
      'name',
      'email',
      'phone_number',
      'country_code',
      'last_activity_at',
      'blocked',
      'labels',
    ]);
  });

  it('a etiqueta é "Não tem a etiqueta", com um "como" só', () => {
    const etiqueta = catalogo().daPessoa.find(
      ({ chave }) => chave === 'labels'
    );
    expect(etiqueta.rotulo).toBe(
      'RELACIONAMENTOS.LISTA.CONDICOES.INFORMACOES.NAO_TEM_ETIQUETA'
    );
    const linhaDaEtiqueta = comInformacao(novaCondicao(1), etiqueta);
    expect(comosDa(linhaDaEtiqueta)).toEqual([OPERADORES.DIFERENTE]);
    expect(linhaDaEtiqueta.como).toBe(OPERADORES.DIFERENTE);
    expect(temUmComoSo(linhaDaEtiqueta)).toBe(true);
  });

  it('"sim ou não" tem um "como" só; campo da conta chamado labels, não', () => {
    expect(temUmComoSo({ chave: 'blocked', tipo: TIPOS.SIM_NAO })).toBe(true);
    expect(temUmComoSo({ chave: 'name', tipo: TIPOS.TEXTO })).toBe(false);
    expect(
      comosDa({ chave: 'labels', tipo: TIPOS.TEXTO, modelo: MODELOS.DA_CONTA })
    ).toEqual(COMO_DO_TIPO[TIPOS.TEXTO]);
  });

  it('"Relação" só entra na conta que tem a chave', () => {
    const relacao = catalogo({ comRelacao: true }).daPessoa.at(-1);
    expect(relacao.chave).toBe('relacao');
    expect(relacao.opcoes.map(({ value }) => value)).toEqual([
      'interessado',
      'parceiro',
      'nao_e_negocio',
    ]);
  });

  it('o país vai como additional; países e etiquetas viram opções', () => {
    const { daPessoa } = catalogo({
      etiquetas: [{ value: 'feira', label: 'feira' }],
    });
    const pais = daPessoa.find(({ chave }) => chave === 'country_code');
    expect(pais.modelo).toBe(MODELOS.ADICIONAL);
    expect(pais.opcoes[0].value).toBe('BR');
    expect(pais.opcoes[0].searchLabel).toBe('Brasil');
    const etiqueta = daPessoa.find(({ chave }) => chave === 'labels');
    expect(etiqueta.opcoes).toEqual([{ value: 'feira', label: 'feira' }]);
  });

  it('os campos da conta vêm com o tipo deles, sem os que repetem a pessoa', () => {
    const { daConta } = catalogo({
      definicoes: [
        {
          attribute_key: 'plano',
          attribute_display_name: 'Plano',
          attribute_display_type: 'list',
          attribute_values: ['Ouro'],
        },
        {
          attribute_key: 'renova_em',
          attribute_display_name: 'Renova em',
          attribute_display_type: 'date',
        },
        { attribute_key: 'vip', attribute_display_type: 'checkbox' },
        { attribute_key: 'city', attribute_display_type: 'text' },
      ],
    });
    expect(daConta).toEqual([
      {
        chave: 'plano',
        rotulo: 'Plano',
        tipo: TIPOS.LISTA,
        modelo: MODELOS.DA_CONTA,
        opcoes: [{ value: 'Ouro', label: 'Ouro' }],
      },
      {
        chave: 'renova_em',
        rotulo: 'Renova em',
        tipo: TIPOS.DATA_DA_CONTA,
        modelo: MODELOS.DA_CONTA,
        opcoes: [],
      },
      {
        chave: 'vip',
        rotulo: 'vip',
        tipo: TIPOS.SIM_NAO,
        modelo: MODELOS.DA_CONTA,
        opcoes: [],
      },
    ]);
  });
});

describe('as linhas', () => {
  it('escolher a informação traz o primeiro "como"; sim ou não nasce em Sim', () => {
    const vazia = novaCondicao(3);
    expect(
      comInformacao(vazia, {
        chave: 'blocked',
        tipo: TIPOS.SIM_NAO,
        modelo: MODELOS.PADRAO,
      })
    ).toEqual({
      id: 3,
      chave: 'blocked',
      tipo: TIPOS.SIM_NAO,
      modelo: MODELOS.PADRAO,
      como: OPERADORES.IGUAL,
      valor: true,
    });
    expect(vazia.chave).toBe('');
  });

  it('trocar o "como" guarda o valor, a não ser que o tipo de valor mude', () => {
    const data = linha({
      chave: 'created_at',
      tipo: TIPOS.DATA,
      como: OPERADORES.DEPOIS,
      valor: '2026-01-10',
    });
    expect(comComo(data, OPERADORES.ANTES).valor).toBe('2026-01-10');
    expect(comComo(data, OPERADORES.HA_MAIS_DE_DIAS).valor).toBe('');
    expect(comComo(data, OPERADORES.PREENCHIDO).valor).toBe('');
  });

  it('erroDaCondicao diz o que falta', () => {
    expect(erroDaCondicao(linha())).toBe('');
    expect(erroDaCondicao(linha({ valor: '  ' }))).toBe('FALTA_TEXTO');
    expect(erroDaCondicao(linha({ tipo: TIPOS.LISTA, valor: '' }))).toBe(
      'FALTA_ESCOLHA'
    );
    const data = { tipo: TIPOS.DATA, como: OPERADORES.DEPOIS };
    expect(erroDaCondicao(linha({ ...data, valor: '' }))).toBe('FALTA_DIA');
    expect(erroDaCondicao(linha({ ...data, valor: '31/02' }))).toBe(
      'DATA_ERRADA'
    );
    expect(erroDaCondicao(linha({ ...data, valor: '2026-02-10' }))).toBe('');
    const dias = { tipo: TIPOS.DATA, como: OPERADORES.HA_MAIS_DE_DIAS };
    expect(erroDaCondicao(linha({ ...dias, valor: '' }))).toBe('FALTA_DIAS');
    expect(erroDaCondicao(linha({ ...dias, valor: '0' }))).toBe('FALTA_DIAS');
    expect(erroDaCondicao(linha({ ...dias, valor: '90' }))).toBe('');
    expect(
      erroDaCondicao(
        linha({
          tipo: TIPOS.DATA_DA_CONTA,
          como: OPERADORES.VAZIO,
          valor: '',
        })
      )
    ).toBe('');
    expect(erroDaCondicao(novaCondicao(9))).toBe('');
  });

  it('condicoesProntas tira a linha sem informação e a que falta valor', () => {
    const pronta = linha({ id: 1 });
    expect(
      condicoesProntas([pronta, novaCondicao(2), linha({ id: 3, valor: '' })])
    ).toEqual([pronta]);
  });
});

describe('paraOServidor (o payload de contacts/filter)', () => {
  it('liga as linhas com and (Tudo isso) e a última vai sem ligação', () => {
    const payload = paraOServidor(
      [
        linha({ id: 1, valor: ' Campinas ' }),
        linha({
          id: 2,
          chave: 'plano',
          tipo: TIPOS.LISTA,
          modelo: MODELOS.DA_CONTA,
          como: OPERADORES.IGUAL,
          valor: 'Ouro',
        }),
      ],
      JUNTAR.TODAS
    );
    expect(payload).toEqual([
      {
        attribute_key: 'city',
        filter_operator: 'contains',
        values: ['Campinas'],
        query_operator: 'and',
        attribute_model: 'standard',
        custom_attribute_type: '',
      },
      {
        attribute_key: 'plano',
        filter_operator: 'equal_to',
        values: ['Ouro'],
        query_operator: undefined,
        attribute_model: 'customAttributes',
        custom_attribute_type: '',
      },
    ]);
  });

  it('"Pelo menos uma" liga com or; "está vazio" vai sem valor', () => {
    const payload = paraOServidor(
      [
        linha({ id: 1 }),
        linha({
          id: 2,
          chave: 'renova_em',
          tipo: TIPOS.DATA_DA_CONTA,
          como: OPERADORES.VAZIO,
          valor: '',
        }),
        linha({ id: 3, valor: '' }),
      ],
      JUNTAR.QUALQUER
    );
    expect(payload.map(item => item.query_operator)).toEqual(['or', undefined]);
    expect(payload[1].values).toEqual([]);
  });
});

describe('os filtros da lista com as condições', () => {
  const condicoes = [linha({ id: 1 }), linha({ id: 2, chave: 'name' })];

  it('cada linha conta 1; "juntar" não conta', () => {
    expect(contarFiltros(FILTROS_VAZIOS)).toBe(0);
    expect(
      contarFiltros({ ...FILTROS_VAZIOS, cidade: 'Santos', condicoes })
    ).toBe(3);
    expect(contarFiltros({ ...FILTROS_VAZIOS, juntar: JUNTAR.QUALQUER })).toBe(
      0
    );
  });

  it('vão ao servidor no parâmetro `condicoes`, só em Pessoas', () => {
    const filtros = { ...FILTROS_VAZIOS, condicoes };
    const params = paramsDoPedido({ aba: 'pessoas', filtros });
    expect(JSON.parse(params.condicoes)).toEqual(paraOServidor(condicoes));
    expect(paramsDoPedido({ aba: 'empresas', filtros })).not.toHaveProperty(
      'condicoes'
    );
    expect(
      paramsDoPedido({ aba: 'pessoas', filtros: FILTROS_VAZIOS })
    ).not.toHaveProperty('condicoes');
  });
});
