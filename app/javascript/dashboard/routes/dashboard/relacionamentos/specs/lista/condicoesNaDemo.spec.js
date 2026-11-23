import {
  JUNTAR,
  MODELOS,
  OPERADORES,
  TIPOS,
  novaCondicao,
} from '../../lista/informacoes';
import {
  pessoaPassaNaCondicao,
  pessoaPassaNasCondicoes,
} from '../../lista/condicoesNaDemo';
import { FILTROS_VAZIOS, pessoaPassaNosFiltros } from '../../lista/filtros';
import { listaFonte } from '../../fonte/listaFonte';
import { pessoas } from '../../demo/base';
import { DIA_EM_MS } from '../../fonte/grupos';

// #3168 — as condições de "Por outra informação" na demonstração: a mesma
// regra de contacts/filter, avaliada no navegador sobre as pessoas fictícias.
const AGORA = new Date(2026, 10, 20, 12).getTime();
const emSegundos = ms => Math.floor(ms / 1000);
const diasAtras = dias => emSegundos(AGORA - dias * DIA_EM_MS);

const pessoa = {
  name: 'Inês Albuquerino',
  email: 'ines@exemplo.com.br',
  blocked: false,
  labels: ['feira', 'site'],
  created_at: emSegundos(new Date(2026, 0, 15, 10).getTime()),
  last_activity_at: diasAtras(120),
  additional_attributes: { city: 'São José dos Campos', company_name: '' },
  custom_attributes: { plano: 'Ouro', renova_em: '2026-12-01' },
};

const condicao = (chave, tipo, como, valor, modelo = MODELOS.PADRAO) => ({
  ...novaCondicao(1),
  chave,
  tipo,
  modelo,
  como,
  valor,
});
const passa = c => pessoaPassaNaCondicao(pessoa, c, AGORA);
const { TEM, NAO_TEM, IGUAL, DIFERENTE, DEPOIS, ANTES, HA_MAIS_DE_DIAS } =
  OPERADORES;

describe('pessoaPassaNaCondicao', () => {
  it('texto: tem e não tem, sem acento nem maiúscula', () => {
    expect(passa(condicao('city', TIPOS.TEXTO, TEM, 'sao jose'))).toBe(true);
    expect(passa(condicao('city', TIPOS.TEXTO, NAO_TEM, 'JOSÉ'))).toBe(false);
    expect(
      passa(condicao('name', TIPOS.TEXTO, IGUAL, 'ines albuquerino'))
    ).toBe(true);
    expect(passa(condicao('name', TIPOS.TEXTO, DIFERENTE, 'Inês'))).toBe(true);
  });

  it('etiqueta: "é" quer dizer que a pessoa tem aquela etiqueta', () => {
    expect(passa(condicao('labels', TIPOS.LISTA, IGUAL, 'feira'))).toBe(true);
    expect(passa(condicao('labels', TIPOS.LISTA, DIFERENTE, 'site'))).toBe(
      false
    );
  });

  it('bloqueada: sim ou não', () => {
    expect(passa(condicao('blocked', TIPOS.SIM_NAO, IGUAL, false))).toBe(true);
    expect(passa(condicao('blocked', TIPOS.SIM_NAO, IGUAL, true))).toBe(false);
  });

  it('campo da conta: lista e data, inclusive preenchido e vazio', () => {
    const daConta = (chave, tipo, como, valor) =>
      condicao(chave, tipo, como, valor, MODELOS.DA_CONTA);
    expect(passa(daConta('plano', TIPOS.LISTA, IGUAL, 'Ouro'))).toBe(true);
    expect(passa(daConta('plano', TIPOS.LISTA, IGUAL, 'Prata'))).toBe(false);
    const data = TIPOS.DATA_DA_CONTA;
    expect(passa(daConta('renova_em', data, DEPOIS, '2026-11-30'))).toBe(true);
    expect(passa(daConta('renova_em', data, ANTES, '2026-12-01'))).toBe(false);
    expect(passa(daConta('renova_em', data, OPERADORES.PREENCHIDO, ''))).toBe(
      true
    );
    expect(passa(daConta('outra', data, OPERADORES.VAZIO, ''))).toBe(true);
  });

  it('data da pessoa: pelo dia e por "há mais de … dias"', () => {
    expect(
      passa(condicao('created_at', TIPOS.DATA, DEPOIS, '2026-01-14'))
    ).toBe(true);
    expect(
      passa(condicao('created_at', TIPOS.DATA, DEPOIS, '2026-01-15'))
    ).toBe(false);
    expect(
      passa(condicao('last_activity_at', TIPOS.DATA, HA_MAIS_DE_DIAS, '90'))
    ).toBe(true);
    expect(
      passa(condicao('last_activity_at', TIPOS.DATA, HA_MAIS_DE_DIAS, '150'))
    ).toBe(false);
  });

  it('quem nunca conversou não passa em "há mais de … dias"', () => {
    const nunca = { ...pessoa, last_activity_at: null };
    expect(
      pessoaPassaNaCondicao(
        nunca,
        condicao('last_activity_at', TIPOS.DATA, HA_MAIS_DE_DIAS, '30'),
        AGORA
      )
    ).toBe(false);
  });
});

describe('pessoaPassaNasCondicoes', () => {
  const sim = condicao('labels', TIPOS.LISTA, IGUAL, 'feira');
  const nao = { ...condicao('city', TIPOS.TEXTO, TEM, 'Santos'), id: 2 };

  it('"Tudo isso" pede todas; "Pelo menos uma" pede uma', () => {
    const condicoes = [sim, nao];
    expect(pessoaPassaNasCondicoes(pessoa, { condicoes }, AGORA)).toBe(false);
    expect(
      pessoaPassaNasCondicoes(
        pessoa,
        { condicoes, juntar: JUNTAR.QUALQUER },
        AGORA
      )
    ).toBe(true);
  });

  it('linha sem informação ou sem valor não conta', () => {
    const incompleta = { ...nao, id: 3, valor: '' };
    expect(
      pessoaPassaNasCondicoes(
        pessoa,
        { condicoes: [sim, incompleta, novaCondicao(4)] },
        AGORA
      )
    ).toBe(true);
    expect(pessoaPassaNasCondicoes(pessoa, {}, AGORA)).toBe(true);
  });

  it('entra junto com os outros filtros da gaveta', () => {
    const filtros = { ...FILTROS_VAZIOS, etiqueta: 'feira', condicoes: [nao] };
    expect(pessoaPassaNosFiltros(pessoa, filtros, AGORA)).toBe(false);
  });
});

describe('a lista da demonstração com condições', () => {
  it('filtra as pessoas fictícias e as contagens batem', async () => {
    const fonte = listaFonte({ demo: 'cheio', atraso: 0 });
    const filtros = {
      ...FILTROS_VAZIOS,
      condicoes: [
        condicao('city', TIPOS.TEXTO, TEM, 'Campinas'),
        {
          ...condicao('last_activity_at', TIPOS.DATA, HA_MAIS_DE_DIAS, '90'),
          id: 2,
        },
      ],
    };
    const agora = Date.now();
    const esperadas = pessoas(agora).filter(p =>
      pessoaPassaNasCondicoes(p, filtros, agora)
    );
    const { total } = await fonte.listar({ aba: 'pessoas', filtros });
    const contagens = await fonte.contagens('pessoas', { filtros });
    expect(esperadas.length).toBeGreaterThan(0);
    expect(esperadas.length).toBeLessThan(280);
    expect(total).toBe(esperadas.length);
    expect(contagens.todos).toBe(esperadas.length);
  });
});
