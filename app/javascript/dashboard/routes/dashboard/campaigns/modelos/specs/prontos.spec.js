import path from 'path';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/modelosWhatsapp.json';
import { CAMPOS, FORMATOS, OBJETIVOS } from '../constants';
import {
  camposUsados,
  conferirConteudo,
  lerTextoComCampos,
  rascunhoDoObjetivo,
} from '../helpers/conteudo';
import { rascunhoDoFormato } from '../helpers/formatos';
import { exemploDoCampo } from '../helpers/campos';
import { corpoParaCriar, podeIrEmCampanha } from '../helpers/paraMeta';
import { BOTOES_SO_DE_DIVULGACAO } from '../helpers/regraEstrutural';

// Todo modelo pronto da galeria (#1380): o rascunho que a tela monta passa na
// conferência, o aviso de serviço não leva nada que só existe em divulgação, e
// o corpo que vai para a Meta fica gravado em spec/fixtures para o lado Ruby
// conferir com a mesma régua do servidor (SubmitFormat) e com o SendableFormat
// da campanha. Atualizar o arquivo: `pnpm test prontos -- -u`.
const IDIOMAS = { en, pt_BR: ptBR };
const FIXTURE = path.resolve(
  process.cwd(),
  'spec/fixtures/whatsapp_templates/prontos.json'
);

// Tradutor mínimo, como o vue-i18n: busca a chave (sem tradução, devolve a
// própria chave) e troca {parametro}.
const tradutor =
  mensagens =>
  (chave, params = {}) => {
    const texto = chave
      .split('.')
      .reduce((nivel, parte) => nivel?.[parte], mensagens);
    if (typeof texto !== 'string') return chave;
    return Object.entries(params).reduce(
      (resultado, [nome, valor]) => resultado.split(`{${nome}}`).join(valor),
      texto
    );
  };

// O que a pessoa faz antes de enviar: escolhe os arquivos e escreve o endereço
// do próprio site e o cupom (o pronto não traz nenhum de fábrica).
const SITE = 'https://sualoja.com.br';
const comSite = botao =>
  botao.tipo === 'site' && !botao.valor ? { ...botao, valor: SITE } : botao;
const preencher = rascunho => {
  const { conteudo } = rascunho;
  const topo =
    conteudo.topo.tipo === 'nenhum'
      ? conteudo.topo
      : { ...conteudo.topo, arquivo: 'arquivo', local: 'blob:arquivo' };
  const extras = {
    ...(conteudo.cartoes && {
      cartoes: conteudo.cartoes.map(cartao => ({
        ...cartao,
        arquivo: 'foto.jpg',
        local: 'blob:foto',
        botoes: cartao.botoes.map(comSite),
      })),
    }),
    ...(conteudo.oferta && {
      oferta: { ...conteudo.oferta, link: SITE, cupom: 'PROMO10' },
    }),
  };
  return {
    ...rascunho,
    conteudo: {
      ...conteudo,
      topo,
      botoes: conteudo.botoes.map(comSite),
      ...extras,
    },
  };
};
const falhasDe = rascunho =>
  conferirConteudo(rascunho.conteudo, { tipo: rascunho.tipo })
    .filter(item => !item.ok)
    .map(item => item.chave);

const midiasDe = ({ conteudo }) => ({
  topo: conteudo.topo.tipo === 'nenhum' ? undefined : { handle: 'HANDLE' },
  cartoes: (conteudo.cartoes || []).map(() => ({ handle: 'HANDLE' })),
});

const prontos = () =>
  Object.entries(IDIOMAS).flatMap(([idioma, mensagens]) => {
    const t = tradutor(mensagens);
    const objetivos = OBJETIVOS.map(objetivo => ({
      origem: 'objetivo',
      chave: objetivo.chave,
      idioma,
      rascunho: rascunhoDoObjetivo(objetivo.chave, { t, campos: CAMPOS }),
    }));
    const formatos = FORMATOS.filter(
      formato => formato.disponivel !== false
    ).map(formato => ({
      origem: 'formato',
      chave: formato.chave,
      idioma,
      rascunho: rascunhoDoFormato(formato.chave, {
        t,
        ler: fonte => lerTextoComCampos(fonte, CAMPOS),
        exemplosDe: texto =>
          Object.fromEntries(
            camposUsados(texto).map(campo => [campo, exemploDoCampo(t, campo)])
          ),
      }),
    }));
    return [...objetivos, ...formatos].map(pronto => {
      // A tela marca o idioma do texto (o da tela) em cada pronto.
      const rascunho = preencher({ ...pronto.rascunho, idioma });
      return {
        ...pronto,
        deFabrica: pronto.rascunho,
        rascunho,
        corpo: corpoParaCriar(rascunho, {
          midias: midiasDe(rascunho),
          textos: {
            botaoDaOferta: t('MODELOS_WHATSAPP.FORMATOS.oferta.BOTAO'),
          },
        }),
      };
    });
  });

describe('modelos prontos (#1380)', () => {
  const lista = prontos();

  it.each(lista.map(pronto => [pronto.idioma, pronto.chave, pronto]))(
    '%s/%s passa na conferência antes de enviar',
    (_idioma, _chave, { rascunho }) => {
      expect(falhasDe(rascunho)).toEqual([]);
    }
  );

  it('nenhum pronto traz endereço, cupom ou marca de fábrica: sem preencher, não envia', () => {
    const pedem = {
      promocao: ['BOTAO_SITE'],
      carrossel: ['CARTOES_MIDIA', 'CARTOES_BOTOES'],
      oferta: ['OFERTA_LINK', 'OFERTA_CUPOM'],
    };
    lista.forEach(({ chave, deFabrica }) => {
      expect(JSON.stringify(deFabrica).toLowerCase(), chave).not.toContain(
        'hub2you'
      );
      expect(falhasDe(deFabrica), chave).toEqual(pedem[chave] || []);
    });
  });

  it('aviso de serviço pronto não tem nada que só existe em divulgação', () => {
    const avisos = lista.filter(pronto => pronto.rascunho.tipo === 'aviso');
    expect(avisos.length).toBeGreaterThan(0);
    avisos.forEach(({ chave, rascunho, corpo }) => {
      const { formato = 'padrao', botoes = [] } = rascunho.conteudo;
      expect(formato, chave).toBe('padrao');
      expect(
        botoes.filter(botao => BOTOES_SO_DE_DIVULGACAO.includes(botao.tipo)),
        chave
      ).toEqual([]);
      expect(corpo.category, chave).toBe('UTILITY');
    });
  });

  it('todo pronto da galeria (objetivo) pode ir em campanha', () => {
    lista
      .filter(pronto => pronto.origem === 'objetivo')
      .forEach(({ chave, rascunho }) =>
        expect(podeIrEmCampanha(rascunho), chave).toBe(true)
      );
  });

  it('"Lembrete de pagamento" é aviso só de texto, com duas respostas rápidas', () => {
    lista
      .filter(pronto => pronto.chave === 'cobranca')
      .forEach(({ corpo, rascunho }) => {
        expect(rascunho.tipo).toBe('aviso');
        expect(rascunho.conteudo.topo.tipo).toBe('nenhum');
        expect(corpo.components.map(item => item.type)).toEqual([
          'BODY',
          'BUTTONS',
        ]);
        expect(corpo.components[1].buttons.map(botao => botao.type)).toEqual([
          'QUICK_REPLY',
          'QUICK_REPLY',
        ]);
        expect(Object.keys(corpo.fields)).toEqual(['1', '2', '3', '4']);
      });
  });

  it('grava os corpos para o lado Ruby conferir', async () => {
    const corpos = lista.map(({ origem, chave, idioma, rascunho, corpo }) => ({
      origem,
      chave,
      idioma,
      pode_ir_em_campanha: podeIrEmCampanha(rascunho),
      corpo,
    }));
    await expect(`${JSON.stringify(corpos, null, 2)}\n`).toMatchFileSnapshot(
      FIXTURE
    );
  });
});
