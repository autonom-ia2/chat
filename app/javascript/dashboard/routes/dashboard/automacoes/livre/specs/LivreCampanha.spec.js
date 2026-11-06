import { mount } from '@vue/test-utils';
import LivreCampanha from '../components/LivreCampanha.vue';
import {
  campanhaPronta,
  caixasDaCampanha,
  comFaz,
  fraseDaCampanha,
  serveNaCampanha,
} from '../campanha';

// #2414 G14 (#2630) — o passo "campanha" no editor: a régua de caixa e modelo
// (a do servidor), o "Salvar" só com a campanha completa e a troca entre
// "mandar" e "não receber" sem levar campo que sobra.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const PRE_BLACK = {
  name: 'pre_black',
  language: 'pt_BR',
  status: 'APPROVED',
  category: 'UTILITY',
  components: [{ type: 'BODY', text: 'Oi! A Black começa {{1}}.' }],
};
const CAIXAS = [
  {
    id: 3,
    name: 'Loja oficial',
    channel_type: 'Channel::Whatsapp',
    provider: 'whatsapp_cloud',
    message_templates: [PRE_BLACK],
  },
  {
    id: 4,
    name: '360',
    channel_type: 'Channel::Whatsapp',
    provider: 'default',
    message_templates: [PRE_BLACK],
  },
  { id: 5, name: 'Site', channel_type: 'Channel::WebWidget' },
];

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: CAIXAS }),
}));

const PRONTA = {
  id: 'c1',
  tipo: 'campanha',
  faz: 'disparar',
  titulo: 'Pré-Black',
  caixa_id: 3,
  modelo: { nome: 'pre_black', idioma: 'pt_BR', variaveis: [['na quinta']] },
  etiquetas: [7],
};

describe('campanha.js', () => {
  it('só caixa do WhatsApp oficial na Cloud API', () => {
    expect(caixasDaCampanha(CAIXAS).map(caixa => caixa.id)).toEqual([3]);
  });

  it('modelo de utilidade ou de propaganda aprovado serve; outro, não', () => {
    expect(serveNaCampanha(PRE_BLACK)).toBe(true);
    expect(serveNaCampanha({ ...PRE_BLACK, category: 'MARKETING' })).toBe(true);
    expect(serveNaCampanha({ ...PRE_BLACK, category: 'AUTHENTICATION' })).toBe(
      false
    );
    expect(serveNaCampanha({ ...PRE_BLACK, status: 'PENDING' })).toBe(false);
  });

  it('pronta só com nome, caixa, modelo com texto em cada variável e etiqueta', () => {
    expect(campanhaPronta(PRONTA)).toBe(true);
    expect(campanhaPronta({ ...PRONTA, titulo: '  ' })).toBe(false);
    expect(campanhaPronta({ ...PRONTA, etiquetas: [] })).toBe(false);
    expect(
      campanhaPronta({
        ...PRONTA,
        modelo: { ...PRONTA.modelo, variaveis: [[]] },
      })
    ).toBe(false);
    expect(
      campanhaPronta({ id: 'n1', tipo: 'campanha', faz: 'nao_receber' })
    ).toBe(true);
  });

  it('voltar para "não receber" tira os campos do disparo', () => {
    expect(comFaz(PRONTA, 'nao_receber')).toEqual({
      id: 'c1',
      tipo: 'campanha',
      faz: 'nao_receber',
    });
  });

  it('frase da linha', () => {
    const t = (chave, valores) =>
      `${chave}${valores ? JSON.stringify(valores) : ''}`;
    expect(fraseDaCampanha(PRONTA, t)).toBe(
      'AUTOMACAO_LIVRE.CAMPANHA.FRASE_DISPARAR{"titulo":"Pré-Black"}'
    );
    expect(fraseDaCampanha({ faz: 'nao_receber' }, t)).toBe(
      'AUTOMACAO_LIVRE.CAMPANHA.FRASE_NAO_RECEBER'
    );
  });
});

describe('LivreCampanha', () => {
  const montar = modelValue =>
    mount(LivreCampanha, {
      props: { modelValue, etiquetas: [{ value: 7, label: 'ja_comprou' }] },
    });

  it('"não receber" mostra só a explicação, sem os campos do disparo', () => {
    const tela = montar({ id: 'n1', tipo: 'campanha', faz: 'nao_receber' });

    expect(tela.text()).toContain('AUTOMACAO_LIVRE.CAMPANHA.NAO_RECEBER_DICA');
    expect(tela.find('[data-campanha-titulo]').exists()).toBe(false);
  });

  it('mandar avisa que só vale no recorrente; modelo de utilidade sem aviso de custo', () => {
    const tela = montar(PRONTA);

    expect(tela.find('[data-campanha-so-recorrente]').exists()).toBe(true);
    expect(tela.find('[data-campanha-custo]').exists()).toBe(false);
  });

  it('modelo de propaganda mostra o aviso de custo', () => {
    CAIXAS[0].message_templates = [{ ...PRE_BLACK, category: 'MARKETING' }];
    const tela = montar(PRONTA);
    CAIXAS[0].message_templates = [PRE_BLACK];

    expect(tela.find('[data-campanha-custo]').exists()).toBe(true);
    expect(tela.text()).toContain('Oi! A Black começa {{1}}.');
    // O nome da campanha e uma caixa por variável do corpo.
    expect(tela.findAllComponents({ name: 'Input' })).toHaveLength(2);
  });

  it('nenhum <select> nativo', () => {
    expect(montar(PRONTA).find('select').exists()).toBe(false);
  });

  it('trocar a caixa limpa o modelo escolhido', async () => {
    const tela = montar(PRONTA);

    const caixa = tela
      .findAllComponents({ name: 'ChoiceSelect' })
      .find(item => item.attributes('data-campanha-caixa') !== undefined);
    caixa.vm.$emit('update:modelValue', 3);

    const [[emitido]] = tela.emitted('update:modelValue');
    expect(emitido.caixa_id).toBe(3);
    expect(emitido.modelo).toBeUndefined();
  });
});
