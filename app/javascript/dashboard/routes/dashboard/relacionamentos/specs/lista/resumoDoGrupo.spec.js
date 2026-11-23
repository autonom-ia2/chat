import { withFullI18n } from 'test-i18n';
import { FILTROS_VAZIOS } from '../../lista/filtros';
import {
  JUNTAR,
  MODELOS,
  OPERADORES,
  TIPOS,
  catalogoDeInformacoes,
} from '../../lista/informacoes';
import { resumoDoGrupo } from '../../lista/resumoDoGrupo';

// #3168 — a frase de quem entra num grupo guardado, com o texto de verdade em
// pt_BR.
const { t } = withFullI18n('pt_BR').global;
const idioma = 'pt-BR';
const opcoes = {
  empresas: [{ value: '7', label: 'Padaria Pão Quente' }],
  etiquetas: [{ value: 'feira', label: 'feira' }],
  cidades: [{ value: 'Campinas', label: 'Campinas' }],
};
const informacoes = catalogoDeInformacoes({
  t,
  idioma,
  etiquetas: opcoes.etiquetas,
  definicoes: [
    {
      attribute_key: 'plano',
      attribute_display_name: 'Plano',
      attribute_display_type: 'list',
      attribute_values: ['Ouro'],
    },
    {
      attribute_key: 'renova_em',
      attribute_display_name: 'Data da renovação',
      attribute_display_type: 'date',
    },
  ],
});
const nomeDoGrupo = id => ({ clientes: 'Clientes' })[id] ?? '';
const resumo = consulta =>
  resumoDoGrupo(
    { grupo: 'todos', busca: '', ...consulta },
    { t, idioma, opcoes, informacoes, nomeDoGrupo }
  );
let proximo = 0;
const linha = (chave, tipo, como, valor, modelo = MODELOS.PADRAO) => {
  proximo += 1;
  return { id: proximo, chave, tipo, modelo, como, valor };
};
const filtros = mais => ({ ...FILTROS_VAZIOS, ...mais });

describe('resumoDoGrupo', () => {
  it('sem nada escolhido, "Todo mundo"', () => {
    expect(resumo({ filtros: FILTROS_VAZIOS })).toBe('Todo mundo');
  });

  it('junta a pílula, a busca e os filtros de cima com os nomes das opções', () => {
    expect(
      resumo({
        grupo: 'clientes',
        busca: 'ana',
        filtros: filtros({ cidade: 'Campinas', empresa: '7' }),
      })
    ).toBe(
      'Clientes · Busca “ana” · Empresa: Padaria Pão Quente · Cidade: Campinas'
    );
  });

  it('escreve cada linha de "Por outra informação" do jeito do leigo', () => {
    const condicoes = [
      linha('name', TIPOS.TEXTO, OPERADORES.TEM, 'Silva'),
      linha('last_activity_at', TIPOS.DATA, OPERADORES.HA_MAIS_DE_DIAS, '90'),
      linha('blocked', TIPOS.SIM_NAO, OPERADORES.IGUAL, true),
      linha('labels', TIPOS.LISTA, OPERADORES.DIFERENTE, 'feira'),
      linha('country_code', TIPOS.LISTA, OPERADORES.IGUAL, 'BR'),
      linha('plano', TIPOS.LISTA, OPERADORES.IGUAL, 'Ouro', MODELOS.DA_CONTA),
      linha(
        'renova_em',
        TIPOS.DATA_DA_CONTA,
        OPERADORES.DEPOIS,
        '2026-12-25',
        MODELOS.DA_CONTA
      ),
      linha(
        'renova_em',
        TIPOS.DATA_DA_CONTA,
        OPERADORES.VAZIO,
        '',
        MODELOS.DA_CONTA
      ),
    ];
    expect(resumo({ filtros: filtros({ condicoes }) }).split(' · ')).toEqual([
      'Nome tem o texto “Silva”',
      'Última conversa há mais de 90 dias',
      'Bloqueada: Sim',
      'Não tem a etiqueta: feira',
      'País é Brasil',
      'Plano é Ouro',
      'Data da renovação depois de 25/12/2026',
      'Data da renovação está vazio',
    ]);
  });

  it('com "Pelo menos uma", as linhas viram uma lista com "ou"', () => {
    const condicoes = [
      linha('name', TIPOS.TEXTO, OPERADORES.IGUAL, 'Ana'),
      linha('email', TIPOS.TEXTO, OPERADORES.NAO_TEM, 'gmail'),
      linha('blocked', TIPOS.SIM_NAO, OPERADORES.IGUAL, false),
    ];
    expect(
      resumo({
        filtros: filtros({ condicoes, juntar: JUNTAR.QUALQUER }),
      })
    ).toBe(
      'Pelo menos uma destas: Nome é exatamente “Ana”, E-mail não tem o texto “gmail” ou Bloqueada: Não'
    );
  });

  it('linha sem valor não entra na frase', () => {
    const condicoes = [linha('name', TIPOS.TEXTO, OPERADORES.TEM, '  ')];
    expect(resumo({ filtros: filtros({ condicoes }) })).toBe('Todo mundo');
  });
});
