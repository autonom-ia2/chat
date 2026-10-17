// @vitest-environment node
// #1550 — trava de cobertura: todo texto do base que fala em ganho/perda tem
// decisão (camada do segmento ou exceção com motivo); exceção velha reprova.
import fs from 'fs';
import os from 'os';
import path from 'path';
import {
  ARQUIVO_EXCECOES,
  checarCatalogo,
  checarCobertura,
  termosDeResultado,
} from '../cobertura.mjs';

const FIXTURES = path.join(__dirname, 'fixtures');
const IDIOMAS = ['en', 'pt_BR'];

const BASE = {
  pt_BR: {
    CRM: { WON: 'Ganho', LOST: 'Perdido', OK: 'Ok' },
    CALLS: { MISSED: 'Chamada perdida' },
  },
  en: {
    CRM: { WON: 'Won', LOST: 'Lost', OK: 'Ok' },
    CALLS: { MISSED: 'Missed call' },
  },
};
const PACOTE = {
  pt_BR: { CRM: { WON: 'Seguro ativo', LOST: 'Não fechou' } },
  en: { CRM: { WON: 'Active policy', LOST: 'Not closed' } },
};

const checar = ({ pacote = PACOTE, excecoes = {}, base = BASE } = {}) =>
  checarCatalogo({
    catalogo: 'painel',
    idiomas: IDIOMAS,
    base: idioma => base[idioma],
    camada: idioma => pacote[idioma],
    pastaDaCamada: 'pacotes/seguros/',
    camadas: idioma => [['seguros', pacote[idioma]]],
    excecoes,
  });

describe('termos de ganho/perda', () => {
  it('pt: acha o pedaço em qualquer forma da palavra', () => {
    expect(termosDeResultado('Negócio ganho', 'pt_BR')).toEqual(['ganh']);
    expect(termosDeResultado('Motivo da perda', 'pt_BR')).toEqual(['perd']);
    expect(termosDeResultado('Ganhou ou perdeu', 'pt_BR')).toEqual([
      'ganh',
      'perd',
    ]);
    expect(termosDeResultado('Seguro ativo', 'pt_BR')).toEqual([]);
  });

  it('en: só palavra inteira, separada por espaço ou pontuação', () => {
    expect(termosDeResultado('Deal won.', 'en')).toEqual(['won']);
    expect(termosDeResultado('Won, lost or archived', 'en')).toEqual([
      'won',
      'lost',
    ]);
    expect(termosDeResultado('Win rate (count)', 'en')).toEqual(['win']);
    expect(termosDeResultado("It won't change", 'en')).toEqual([]);
    expect(termosDeResultado('Window and winner', 'en')).toEqual([]);
  });

  it('ignora o nome do parâmetro', () => {
    expect(termosDeResultado('{won} fecharam', 'pt_BR')).toEqual([]);
    expect(termosDeResultado('{won} closed', 'en')).toEqual([]);
    expect(termosDeResultado('%{lost} cards', 'en')).toEqual([]);
  });

  // Revisão do Codex (#1579): literal e aspas não podem esconder a palavra.
  it("lê o literal {'...'}, que aparece na tela", () => {
    expect(termosDeResultado("Status: {'Won'}", 'en')).toEqual(['won']);
    expect(termosDeResultado("Status: {'Ganho'}", 'pt_BR')).toEqual(['ganh']);
    expect(termosDeResultado("{'@'}{won}", 'en')).toEqual([]);
  });

  it('trata aspa na ponta como pontuação e mantém a contração', () => {
    expect(termosDeResultado("Deal 'won'", 'en')).toEqual(['won']);
    expect(termosDeResultado('Deal ’lost’', 'en')).toEqual(['lost']);
    expect(termosDeResultado("It won't change", 'en')).toEqual([]);
  });
});

describe('cobertura de um catálogo', () => {
  it('caso coberto: o pacote troca a chave, sem erro', () => {
    expect(
      checar({ excecoes: { 'CALLS.MISSED': 'Ligação perdida.' } })
    ).toEqual([]);
  });

  it('caso exceção: chave fora do pacote com motivo, sem erro', () => {
    const pacote = {
      pt_BR: { CRM: { WON: 'Seguro ativo' } },
      en: { CRM: { WON: 'Active policy' } },
    };
    expect(
      checar({
        pacote,
        excecoes: {
          'CRM.LOST': 'Motivo de teste.',
          'CALLS.MISSED': 'Ligação perdida.',
        },
      })
    ).toEqual([]);
  });

  it('caso faltando: reprova e diz o que fazer', () => {
    const erros = checar();
    expect(erros).toHaveLength(1);
    expect(erros[0]).toContain('painel pt_BR CALLS.MISSED');
    expect(erros[0]).toContain('("Chamada perdida") fala em perd');
    expect(erros[0]).toContain('pacotes/seguros/');
    expect(erros[0]).toContain(ARQUIVO_EXCECOES);
  });

  it('cobra os dois idiomas: falta no en também reprova', () => {
    const base = {
      pt_BR: BASE.pt_BR,
      en: { ...BASE.en, CALLS: { MISSED: 'Lost call' } },
    };
    const erros = checar({ base });
    expect(erros.map(erro => erro.split(' (')[0])).toEqual([
      'painel en CALLS.MISSED',
      'painel pt_BR CALLS.MISSED',
    ]);
  });

  it('exceção órfã: chave que não existe mais no base reprova', () => {
    const erros = checar({
      excecoes: { 'CALLS.MISSED': 'Ligação perdida.', 'CRM.SUMIU': 'Velha.' },
    });
    expect(erros).toEqual([
      `${ARQUIVO_EXCECOES} > painel > CRM.SUMIU: a chave não existe mais no catálogo base; tire da lista`,
    ]);
  });

  it('exceção órfã: texto que não fala mais em ganho/perda reprova', () => {
    const erros = checar({
      excecoes: { 'CALLS.MISSED': 'Ligação perdida.', 'CRM.OK': 'Velha.' },
    });
    expect(erros).toEqual([
      `${ARQUIVO_EXCECOES} > painel > CRM.OK: o texto não fala mais em ganho/perda; tire da lista`,
    ]);
  });

  it('reprova exceção sem motivo e chave no pacote e nas exceções', () => {
    const erros = checar({
      excecoes: { 'CALLS.MISSED': ' ', 'CRM.WON': 'Duplicada.' },
    });
    expect(erros).toEqual([
      `${ARQUIVO_EXCECOES} > painel > CALLS.MISSED: falta o motivo`,
      `${ARQUIVO_EXCECOES} > painel > CRM.WON: a chave está no pacote e nas exceções; fique com um dos dois`,
    ]);
  });

  it('reprova texto do próprio pacote que ainda fala em ganho/perda', () => {
    const pacote = {
      pt_BR: { CRM: { WON: 'Seguro ganho', LOST: 'Não fechou' } },
      en: { CRM: { WON: 'Active policy', LOST: 'Not closed' } },
    };
    expect(
      checar({ pacote, excecoes: { 'CALLS.MISSED': 'Ligação perdida.' } })
    ).toEqual([
      'painel pt_BR CRM.WON: o texto da camada seguros ainda fala em ganh',
    ]);
  });
});

describe('cobertura com os arquivos (painel e servidor)', () => {
  const pastas = [];
  afterAll(() => {
    pastas.forEach(pasta => fs.rmSync(pasta, { recursive: true, force: true }));
  });
  const comExcecoes = conteudo => {
    const pasta = fs.mkdtempSync(path.join(os.tmpdir(), 'cobertura-1550-'));
    pastas.push(pasta);
    const arquivo = path.join(pasta, 'fora-do-pacote.json');
    fs.writeFileSync(arquivo, JSON.stringify(conteudo));
    return arquivo;
  };
  const PACOTES = {
    painel: path.join(FIXTURES, 'valido', 'painel'),
    servidor: path.join(FIXTURES, 'valido', 'servidor'),
    idiomas: IDIOMAS,
    segmentos: { seguros: ['saude_beneficios'] },
  };
  const rodar = excecoes =>
    checarCobertura(PACOTES, {
      excecoes,
      dirLocalesPainel: path.join(FIXTURES, 'locale'),
      dirLocalesServidor: path.join(FIXTURES, 'locales'),
    });

  it('acusa no painel e no servidor o que o pacote válido não troca', () => {
    const erros = rodar(comExcecoes({ painel: {}, servidor: {} }));
    expect(erros.map(erro => erro.split(' (')[0])).toEqual([
      'painel en CRM.LOST',
      'painel pt_BR CRM.LOST',
      'servidor en crm.export.statuses.lost',
      'servidor pt_BR crm.export.statuses.lost',
    ]);
  });

  it('passa quando o que falta está nas exceções', () => {
    const arquivo = comExcecoes({
      painel: { 'CRM.LOST': 'Teste.' },
      servidor: { 'crm.export.statuses.lost': 'Teste.' },
    });
    expect(rodar(arquivo)).toEqual([]);
  });

  it('reprova quando o arquivo de exceções não existe', () => {
    expect(rodar('/nao/existe.json')).toEqual([
      '/nao/existe.json: arquivo de exceções não existe',
    ]);
  });

  it('reprova registro sem segmento, em vez de passar calado', () => {
    const arquivo = comExcecoes({ painel: {}, servidor: {} });
    const inicio = 'config/fork_i18n.json > pacotes.segmentos:';
    [undefined, {}].forEach(segmentos => {
      const pacotes = { ...PACOTES, segmentos };
      const erros = checarCobertura(pacotes, { excecoes: arquivo });
      expect(erros).toHaveLength(1);
      expect(erros[0].startsWith(inicio)).toBe(true);
    });
  });
});

describe('pacotes reais do repositório', () => {
  it('cobrem todo ganho/perda do base, com as exceções versionadas', () => {
    const registro = JSON.parse(
      fs.readFileSync('config/fork_i18n.json', 'utf8')
    );
    expect(checarCobertura(registro.pacotes)).toEqual([]);
  });
});
