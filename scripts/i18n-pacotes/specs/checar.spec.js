// @vitest-environment node
// #1550 — o checador dos pacotes de tradução reprova o que quebraria em silêncio:
// chave que não existe no base, idioma faltando, parâmetro trocado e camada inventada.
import fs from 'fs';
import os from 'os';
import path from 'path';
import YAML from 'yaml';
import {
  baseDoPainel,
  baseDoServidor,
  camadasValidas,
  checarCrowdin,
  checarPacotes,
  checarPainel,
  checarServidor,
  parametrosRuby,
} from '../checar.mjs';

const FIXTURES = path.join(__dirname, 'fixtures');
const LOCALE = path.join(FIXTURES, 'locale');
const LOCALES = path.join(FIXTURES, 'locales');
const PACOTES = {
  painel: 'painel',
  servidor: 'servidor',
  idiomas: ['en', 'pt_BR'],
  segmentos: { seguros: ['corretora', 'saude_beneficios'] },
};

const pastasTemporarias = [];
// Cópia do pacote válido numa pasta temporária, para cada caso estragar o seu.
const copiaDoValido = () => {
  const destino = fs.mkdtempSync(path.join(os.tmpdir(), 'pacotes-1550-'));
  pastasTemporarias.push(destino);
  fs.cpSync(path.join(FIXTURES, 'valido'), destino, { recursive: true });
  return destino;
};
const escrever = (raiz, relativo, conteudo) => {
  const arquivo = path.join(raiz, relativo);
  fs.mkdirSync(path.dirname(arquivo), { recursive: true });
  fs.writeFileSync(arquivo, conteudo);
};
const painel = raiz =>
  checarPainel({
    raiz: path.join(raiz, 'painel'),
    dirLocales: LOCALE,
    pacotes: PACOTES,
  });
const servidor = raiz =>
  checarServidor({
    raiz: path.join(raiz, 'servidor'),
    dirLocales: LOCALES,
    pacotes: PACOTES,
  });

afterAll(() => {
  pastasTemporarias.forEach(pasta =>
    fs.rmSync(pasta, { recursive: true, force: true })
  );
});

describe('peças do checador', () => {
  it('lista as camadas do registro: o segmento e cada tipo', () => {
    expect(camadasValidas(PACOTES)).toEqual([
      'seguros',
      'seguros/corretora',
      'seguros/saude_beneficios',
    ]);
  });

  it('lê os parâmetros %{x} do Rails sem regex', () => {
    expect(parametrosRuby('%{b} de %{a}, %{a}')).toEqual(['a', 'b']);
    expect(parametrosRuby('sem parâmetro')).toEqual([]);
    expect(parametrosRuby('aberto %{sem fim')).toEqual([]);
  });

  it('monta o base do painel pelo index.js, como o painel monta', () => {
    const base = baseDoPainel(path.join(LOCALE, 'pt_BR'));
    expect(base.CRM.WON).toBe('Ganho');
    expect(base.GERAL.OK).toBe('Ok');
  });

  it('monta o base do servidor só com os yml cuja raiz é o idioma', () => {
    expect(baseDoServidor(LOCALES, 'en').outro.titulo).toBe('Other');
    expect(baseDoServidor(LOCALES, 'pt_BR').outro).toBeUndefined();
    expect(baseDoServidor(LOCALES, 'pt_BR').crm.export.statuses.won).toBe(
      'Ganho'
    );
  });
});

describe('pacote do painel', () => {
  it('aceita o pacote válido', () => {
    expect(painel(copiaDoValido())).toEqual([]);
  });

  it('(a) reprova chave que não existe no base ou que lá é um grupo', () => {
    const raiz = copiaDoValido();
    escrever(
      raiz,
      'painel/seguros/en.json',
      '{ "CRM": { "WON": "x", "COUNT": "{count} x", "NOVA": "x" } }'
    );
    escrever(
      raiz,
      'painel/seguros/pt_BR.json',
      '{ "CRM": { "WON": "x", "COUNT": "{count} x", "GROUP": "x" } }'
    );

    const erros = painel(raiz);
    expect(
      erros.some(
        e => e.includes('en.json:CRM.NOVA') && e.includes('catálogo base')
      )
    ).toBe(true);
    expect(
      erros.some(
        e => e.includes('pt_BR.json:CRM.GROUP') && e.includes('catálogo base')
      )
    ).toBe(true);
  });

  it('(b) reprova idiomas com chaves diferentes, idioma faltando e idioma fora da lista', () => {
    const raiz = copiaDoValido();
    escrever(
      raiz,
      'painel/seguros/en.json',
      '{ "CRM": { "WON": "Active policy" } }'
    );
    fs.rmSync(path.join(raiz, 'painel/seguros/saude_beneficios/pt_BR.json'));
    escrever(
      raiz,
      'painel/seguros/saude_beneficios/es.json',
      '{ "CRM": { "WON": "x" } }'
    );

    const erros = painel(raiz);
    expect(
      erros.some(e =>
        e.endsWith('painel/seguros: pt_BR.json e en.json têm chaves diferentes')
      )
    ).toBe(true);
    expect(
      erros.some(e => e.endsWith('saude_beneficios: falta pt_BR.json'))
    ).toBe(true);
    expect(
      erros.some(e => e.includes('saude_beneficios/es.json: arquivo fora de'))
    ).toBe(true);
  });

  it('(c) reprova parâmetro diferente do base', () => {
    const raiz = copiaDoValido();
    escrever(
      raiz,
      'painel/seguros/pt_BR.json',
      '{ "CRM": { "WON": "Seguro ativo", "COUNT": "{total} apólices" } }'
    );

    expect(painel(raiz)).toEqual([
      expect.stringContaining(
        'pt_BR.json:CRM.COUNT: parâmetros [total] diferem do base [count]'
      ),
    ]);
  });

  it('(d) reprova camada fora do registro e mensagem vazia', () => {
    const raiz = copiaDoValido();
    escrever(raiz, 'painel/varejo/en.json', '{ "CRM": { "WON": "x" } }');
    escrever(
      raiz,
      'painel/seguros/saude_beneficios/en.json',
      '{ "CRM": { "WON": "  " } }'
    );

    const erros = painel(raiz);
    expect(erros.some(e => e.includes('painel/varejo: camada fora de'))).toBe(
      true
    );
    expect(
      erros.some(e =>
        e.includes('saude_beneficios/en.json:CRM.WON: mensagem vazia')
      )
    ).toBe(true);
  });
});

describe('pacote do servidor', () => {
  it('aceita o pacote válido', () => {
    expect(servidor(copiaDoValido())).toEqual([]);
  });

  it('(a) reprova chave que não existe no base do mesmo idioma', () => {
    const raiz = copiaDoValido();
    escrever(
      raiz,
      'servidor/seguros/pt_BR.yml',
      YAML.stringify({
        pt_BR: {
          crm: {
            export: {
              statuses: { won: 'Seguro ativo' },
              count: '%{count} apólices',
            },
          },
          outro: { titulo: 'x' },
        },
      })
    );

    const erros = servidor(raiz);
    expect(erros).toHaveLength(2);
    expect(
      erros.some(e =>
        e.includes('pt_BR.yml:outro.titulo: não é folha de texto')
      )
    ).toBe(true);
    expect(erros.some(e => e.includes('têm chaves diferentes'))).toBe(true);
  });

  it('(b) reprova idioma faltando', () => {
    const raiz = copiaDoValido();
    fs.rmSync(path.join(raiz, 'servidor/seguros/en.yml'));

    expect(servidor(raiz)).toEqual([
      expect.stringContaining('servidor/seguros: falta en.yml'),
    ]);
  });

  it('(c) reprova %{x} diferente do base', () => {
    const raiz = copiaDoValido();
    escrever(
      raiz,
      'servidor/seguros/en.yml',
      YAML.stringify({
        en: {
          crm: {
            export: { statuses: { won: 'Active policy' }, count: 'policies' },
          },
        },
      })
    );

    expect(servidor(raiz)).toEqual([
      expect.stringContaining(
        'en.yml:crm.export.count: parâmetros [] diferem do base [count]'
      ),
    ]);
  });

  it('(d) reprova raiz do yml diferente do nome do arquivo', () => {
    const raiz = copiaDoValido();
    escrever(
      raiz,
      'servidor/seguros/pt_BR.yml',
      YAML.stringify({
        en: {
          crm: {
            export: {
              statuses: { won: 'Seguro ativo' },
              count: '%{count} apólices',
            },
          },
        },
      })
    );

    expect(servidor(raiz)).toEqual([
      expect.stringContaining(
        'pt_BR.yml: a raiz do yml precisa ser só "pt_BR:"'
      ),
    ]);
  });
});

describe('Crowdin', () => {
  it('reprova fonte que cobre a pasta de pacotes', () => {
    const crowdin = {
      files: [
        { source: '/config/pacotes/**/en.yml' },
        { source: '/config/**/*.yml' },
      ],
    };
    expect(
      checarCrowdin(crowdin, { painel: 'app/x', servidor: 'config/pacotes' })
    ).toHaveLength(2);
  });

  it('aceita fonte em outra pasta', () => {
    const crowdin = { files: [{ source: '/config/locales/en.yml' }] };
    expect(
      checarCrowdin(crowdin, { painel: 'app/x', servidor: 'config/pacotes' })
    ).toEqual([]);
  });
});

describe('pacotes reais do repositório', () => {
  it('passam no checador, com o crowdin.yml real', () => {
    const registro = JSON.parse(
      fs.readFileSync('config/fork_i18n.json', 'utf8')
    );
    const crowdin = YAML.parse(fs.readFileSync('crowdin.yml', 'utf8'));

    expect(checarPacotes(registro.pacotes, { crowdin })).toEqual([]);
  });

  it('reprova registro sem a chave pacotes', () => {
    expect(checarPacotes(undefined)).toEqual([
      'config/fork_i18n.json: falta a chave "pacotes"',
    ]);
  });
});
