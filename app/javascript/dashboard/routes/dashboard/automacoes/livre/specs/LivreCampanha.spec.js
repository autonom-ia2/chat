import { mount } from '@vue/test-utils';
import LivreCampanha from '../components/LivreCampanha.vue';
import {
  campanhaPronta,
  caixasDaCampanha,
  comFaz,
  comPublico,
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
    expect(campanhaPronta(PRONTA, CAIXAS)).toBe(true);
    expect(campanhaPronta({ ...PRONTA, titulo: '  ' }, CAIXAS)).toBe(false);
    expect(campanhaPronta({ ...PRONTA, etiquetas: [] }, CAIXAS)).toBe(false);
    expect(
      campanhaPronta(
        { ...PRONTA, modelo: { ...PRONTA.modelo, variaveis: [[]] } },
        CAIXAS
      )
    ).toBe(false);
    expect(
      campanhaPronta({ id: 'n1', tipo: 'campanha', faz: 'nao_receber' })
    ).toBe(true);
  });

  // Exemplo 7, passo 2: "a mesma campanha para todos os outros contatos".
  it('"todos os contatos" fica pronta sem etiqueta de público', () => {
    const todos = comPublico(PRONTA, 'todos');

    expect(todos.publico).toBe('todos');
    expect(todos).not.toHaveProperty('etiquetas');
    expect(campanhaPronta({ ...todos, sem_etiquetas: [7] }, CAIXAS)).toBe(true);
  });

  it('voltar para "quem tem as etiquetas" tira o "todos"', () => {
    const volta = comPublico({ ...PRONTA, publico: 'todos' }, 'etiquetas');

    expect(volta).not.toHaveProperty('publico');
    expect(volta.etiquetas).toEqual([7]);
    expect(
      campanhaPronta(comPublico({ ...PRONTA, etiquetas: [] }, 'etiquetas'))
    ).toBe(false);
  });

  it('modelo que sumiu da caixa, ou caixa que não é a oficial, não salva', () => {
    const sumiu = { ...PRONTA, modelo: { ...PRONTA.modelo, nome: 'antigo' } };
    expect(campanhaPronta(sumiu, CAIXAS)).toBe(false);
    expect(campanhaPronta({ ...PRONTA, caixa_id: 4 }, CAIXAS)).toBe(false);
    expect(campanhaPronta(PRONTA, [])).toBe(false);
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

  it('"menos quem tem" grava as etiquetas excluídas, sem tirar as do público', async () => {
    const tela = montar(PRONTA);

    const [, sem] = tela.findAllComponents({ name: 'LivreMarcar' });
    sem.vm.$emit('update:modelValue', [7]);

    const [[emitido]] = tela.emitted('update:modelValue');
    expect(emitido).toMatchObject({ etiquetas: [7], sem_etiquetas: [7] });
    expect(tela.text()).toContain(
      'AUTOMACAO_LIVRE.CAMPANHA.SEM_ETIQUETAS_DICA'
    );
  });

  it('"não receber" deixa as etiquetas excluídas de fora', () => {
    expect(
      comFaz({ ...PRONTA, sem_etiquetas: [7] }, 'nao_receber')
    ).not.toHaveProperty('sem_etiquetas');
  });

  it('escolher "todos os contatos" esconde as etiquetas do público e mantém o "menos quem tem"', async () => {
    const tela = montar(PRONTA);

    const publico = tela
      .findAllComponents({ name: 'ChoiceSelect' })
      .find(item => item.attributes('data-campanha-publico') !== undefined);
    publico.vm.$emit('update:modelValue', 'todos');

    const [[emitido]] = tela.emitted('update:modelValue');
    expect(emitido.publico).toBe('todos');
    expect(emitido).not.toHaveProperty('etiquetas');

    await tela.setProps({ modelValue: { ...emitido, sem_etiquetas: [7] } });
    expect(tela.findAllComponents({ name: 'LivreMarcar' })).toHaveLength(1);
    expect(tela.find('[data-campanha-sem]').exists()).toBe(true);
    expect(tela.text()).toContain(
      'AUTOMACAO_LIVRE.CAMPANHA.PUBLICO_TODOS_DICA'
    );
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
