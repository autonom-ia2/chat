import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import EtapaExtras from '../components/criar/EtapaExtras.vue';
import { conferirConteudo, podeEnviar } from '../helpers/conteudo';
import { conferirFormato } from '../helpers/formatos';
import {
  codigoDeExemploValido,
  problemasDoBotao,
} from '../helpers/regraEstrutural';
import { recusaDe } from '../api/daMeta';

// A forma dos botões que a Meta exige (#1380): a mesma régua do servidor
// (Whatsapp::Templates::SubmitFormat), antes de enviar.
const conteudo = botoes => ({
  formato: 'padrao',
  topo: { tipo: 'nenhum', arquivo: '' },
  texto: [{ t: 'texto', v: 'Olá! Seu pedido saiu.' }],
  exemplos: {},
  rodape: '',
  botoes,
});
const falhas = (botoes, tipo) =>
  conferirConteudo(conteudo(botoes), { tipo })
    .filter(item => !item.ok)
    .map(item => item.chave);

describe('código de exemplo do "Copiar código"', () => {
  it.each([
    ['PROMO10', true],
    ['A', true],
    ['ABCDEFGHIJ12345', true],
    ['', false],
    [undefined, false],
    ['ABCDEFGHIJ123456', false],
    ['2345 6789', false],
    ['PROMO-10', false],
    ['CAFÉ', false],
  ])('%s → %s', (codigo, valido) => {
    expect(codigoDeExemploValido(codigo)).toBe(valido);
  });
});

describe('problemas de cada botão', () => {
  it('copiar código num aviso de serviço: só existe em divulgação', () => {
    const botao = { tipo: 'copiar_codigo', texto: 'Copiar', valor: 'PROMO10' };
    expect(problemasDoBotao(botao, 'aviso')).toEqual(['SO_DIVULGACAO']);
    expect(problemasDoBotao(botao, 'divulgacao')).toEqual([]);
  });

  it('acusa cada campo obrigatório que falta', () => {
    expect(
      problemasDoBotao({ tipo: 'site', texto: '', valor: '' }, 'aviso')
    ).toEqual(['SEM_TEXTO', 'SITE_SEM_ENDERECO']);
    expect(
      problemasDoBotao({ tipo: 'ligar', texto: 'Ligar', valor: ' ' }, 'aviso')
    ).toEqual(['LIGAR_SEM_NUMERO']);
    expect(
      problemasDoBotao(
        { tipo: 'copiar_codigo', texto: 'Copiar', valor: '' },
        'divulgacao'
      )
    ).toEqual(['CODIGO_SEM_EXEMPLO']);
    expect(
      problemasDoBotao({ tipo: 'resposta', texto: 'Ok', valor: '' }, 'aviso')
    ).toEqual([]);
  });
});

describe('conferência antes de enviar', () => {
  it('o pronto antigo do boleto (copiar código sem código, num aviso) não envia', () => {
    const botoes = [
      { tipo: 'copiar_codigo', texto: 'Copiar código', valor: '' },
    ];
    expect(falhas(botoes, 'aviso')).toEqual(['SO_DIVULGACAO']);
    expect(podeEnviar(conteudo(botoes), { tipo: 'aviso' })).toBe(false);
    expect(falhas(botoes, 'divulgacao')).toEqual(['BOTAO_CODIGO']);
  });

  it('site sem endereço e ligar sem número não enviam', () => {
    expect(
      falhas(
        [
          { tipo: 'site', texto: 'Ver', valor: '' },
          { tipo: 'ligar', texto: 'Ligar', valor: '' },
        ],
        'aviso'
      )
    ).toEqual(['BOTAO_SITE', 'BOTAO_LIGAR']);
  });

  it('mostra só as regras dos botões que existem', () => {
    const chaves = conferirConteudo(conteudo([]), { tipo: 'aviso' }).map(
      item => item.chave
    );
    expect(chaves).toContain('BOTOES');
    expect(chaves).not.toContain('BOTAO_SITE');
    expect(chaves).not.toContain('SO_DIVULGACAO');
  });

  it('oferta sem cupom válido não envia (a contagem exige o botão de copiar)', () => {
    const oferta = cupom => ({
      formato: 'oferta',
      oferta: {
        titulo: 'Só hoje',
        terminaEm: '2999-01-01T10:00',
        link: 'https://h.com',
        cupom,
      },
    });
    const cupom = valor =>
      conferirFormato(oferta(valor)).find(item => item.chave === 'OFERTA_CUPOM')
        .ok;
    expect(cupom('HUB30')).toBe(true);
    expect(cupom('')).toBe(false);
    expect(cupom('HUB 30')).toBe(false);
  });

  it('cartão de carrossel com botão de site sem endereço não envia', () => {
    const cartao = valor => ({
      local: 'blob:x',
      texto: 'Novidade',
      botoes: [{ tipo: 'site', texto: 'Ver', valor }],
    });
    const botoesOk = cartoes =>
      conferirFormato({ formato: 'carrossel', cartoes }).find(
        item => item.chave === 'CARTOES_BOTOES'
      ).ok;
    expect(botoesOk([cartao('https://h.com'), cartao('https://h.com')])).toBe(
      true
    );
    expect(botoesOk([cartao('https://h.com'), cartao('')])).toBe(false);
  });
});

describe('recusa da Meta por botão de copiar sem código', () => {
  it('explica o motivo na tela de corrigir', () => {
    const recusado = {
      texto: [{ t: 'texto', v: 'Seu boleto.' }],
      exemplos: {},
      botoes: [{ tipo: 'copiar_codigo', texto: '', valor: '' }],
    };
    expect(recusaDe({ rejected_reason: 'INVALID_FORMAT' }, recusado)).toEqual({
      codigo: 'botao_copiar_codigo',
    });
  });
});

describe('editor de botões', () => {
  const montar = (tipo, botoes) =>
    mount(EtapaExtras, {
      props: {
        rascunho: { tipo, conteudo: conteudo(botoes) },
        'onUpdate:rascunho': () => {},
      },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
        ],
      },
    });

  it('num aviso, avisa que o botão só existe em divulgação', () => {
    const wrapper = montar('aviso', [
      { tipo: 'copiar_codigo', texto: 'Copiar código', valor: '' },
    ]);
    expect(wrapper.find('[data-so-divulgacao]').text()).toBe(
      en.MODELOS_WHATSAPP.EXTRAS.PROBLEMAS_DO_BOTAO.SO_DIVULGACAO
    );
  });

  it('num aviso, "Copiar código" não aparece para escolher', async () => {
    const wrapper = montar('aviso', []);
    await wrapper.find('[data-adicionar-botao]').trigger('click');
    expect(
      wrapper.find('[data-tipo-botao="copiar_codigo"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.find('[data-tipo-botao="site"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('diz no campo o que falta', () => {
    const wrapper = montar('divulgacao', [
      { tipo: 'copiar_codigo', texto: 'Copiar', valor: '2345 6789' },
    ]);
    expect(wrapper.text()).toContain(
      en.MODELOS_WHATSAPP.EXTRAS.PROBLEMAS_DO_BOTAO.CODIGO_SEM_EXEMPLO
    );
  });
});
