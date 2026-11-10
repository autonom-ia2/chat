import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreModelo from '../components/LivreModelo.vue';
import LivreTexto from '../components/LivreTexto.vue';
import { modelosDasCaixas, serve, variaveisDoCorpo } from '../modeloWhatsapp';

// #2468 F4b — o modelo aprovado do passo "mensagem": só os de utilidade ou de
// propaganda (lote 5, #2681) aprovados e preenchíveis das caixas oficiais, um por nome e idioma; cada
// variável vira uma caixa de texto; "não mandar nada" tira o modelo.
const caixas = ref([]);
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => caixas,
}));
const traduzir = (chave, valores) =>
  valores ? `${chave}(${Object.values(valores).join(',')})` : chave;
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: traduzir }),
}));

const APROVADO = {
  name: 'pedido_saiu',
  language: 'pt_BR',
  status: 'APPROVED',
  category: 'UTILITY',
  components: [{ type: 'BODY', text: 'Oi {{1}}, seu pedido {{2}} saiu.' }],
};
const OFICIAL = { channel_type: 'Channel::Whatsapp' };

const montar = (props = {}) =>
  mount(LivreModelo, {
    props: {
      rotulo: 'Se a janela de 24 h estiver fechada',
      catalogo: { valores: [] },
      atributosDo: () => [],
      ...props,
    },
    global: {
      mocks: { $t: traduzir },
      stubs: {
        ChoiceSelect: {
          props: ['options', 'modelValue'],
          emits: ['update:modelValue'],
          template:
            '<div data-opcoes>{{ options.map(o => o.label).join("|") }}</div>',
        },
        LivreTexto: {
          props: ['rotulo', 'modelValue'],
          template: '<div data-variavel>{{ rotulo }}</div>',
        },
      },
    },
  });

describe('modeloWhatsapp', () => {
  it('lê as variáveis do corpo sem repetir', () => {
    expect(variaveisDoCorpo('Oi {{1}}, {{2}} e {{1}}')).toEqual(['1', '2']);
  });

  it('serve: aprovado, de utilidade ou propaganda, {{1}}..{{n}} e sem mídia no topo', () => {
    expect(serve(APROVADO)).toBe(true);
    expect(serve({ ...APROVADO, category: 'MARKETING' })).toBe(true);
    expect(serve({ ...APROVADO, category: 'AUTHENTICATION' })).toBe(false);
    expect(serve({ ...APROVADO, status: 'PENDING' })).toBe(false);
    expect(
      serve({
        ...APROVADO,
        components: [
          { type: 'HEADER', format: 'IMAGE' },
          ...APROVADO.components,
        ],
      })
    ).toBe(false);
    expect(
      serve({ ...APROVADO, components: [{ type: 'BODY', text: 'Oi {{2}}' }] })
    ).toBe(false);
  });

  it('junta as caixas oficiais, um modelo por nome e idioma', () => {
    const lista = modelosDasCaixas([
      { ...OFICIAL, message_templates: [APROVADO] },
      { ...OFICIAL, message_templates: [APROVADO] },
      { channel_type: 'Channel::Api', message_templates: [APROVADO] },
    ]);
    expect(lista).toHaveLength(1);
    expect(lista[0].divergente).toBeUndefined();
  });

  it('mesmo nome e idioma com outro corpo em outra caixa: divergente', () => {
    const outro = {
      ...APROVADO,
      components: [{ type: 'BODY', text: 'Olá {{1}}, pedido {{2}}.' }],
    };
    const lista = modelosDasCaixas([
      { ...OFICIAL, message_templates: [APROVADO] },
      { ...OFICIAL, message_templates: [outro] },
    ]);
    expect(lista).toHaveLength(1);
    expect(lista[0].divergente).toBe(true);
    expect(APROVADO.divergente).toBeUndefined();
  });
});

describe('LivreModelo', () => {
  beforeEach(() => {
    caixas.value = [{ ...OFICIAL, message_templates: [APROVADO] }];
  });

  it('lista "não mandar nada" e os modelos que servem', () => {
    expect(montar().find('[data-opcoes]').text()).toBe(
      'AUTOMACAO_LIVRE.ALTERAR_PAINEL.MODELO.NENHUM|AUTOMACAO_LIVRE.ALTERAR_PAINEL.MODELO.OPCAO(pedido_saiu,pt_BR)'
    );
  });

  it('escolher monta o modelo com uma variável vazia por posição', async () => {
    const wrapper = montar();
    await wrapper
      .findComponent(ChoiceSelect)
      .vm.$emit('update:modelValue', 'pedido_saiu|pt_BR');

    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual({
      nome: 'pedido_saiu',
      idioma: 'pt_BR',
      variaveis: [[], []],
    });
  });

  it('"não mandar nada" tira o modelo', async () => {
    const wrapper = montar({
      modelValue: { nome: 'pedido_saiu', idioma: 'pt_BR', variaveis: [[], []] },
    });
    await wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', '');

    expect(wrapper.emitted('update:modelValue')[0][0]).toBeNull();
  });

  it('com o modelo escolhido, mostra o corpo e uma caixa por variável, na ordem', () => {
    const wrapper = montar({
      modelValue: { nome: 'pedido_saiu', idioma: 'pt_BR', variaveis: [[], []] },
    });

    expect(wrapper.find('[data-corpo-do-modelo]').text()).toBe(
      'Oi {{1}}, seu pedido {{2}} saiu.'
    );
    expect(wrapper.findAll('[data-variavel]').map(v => v.text())).toEqual([
      'AUTOMACAO_LIVRE.ALTERAR_PAINEL.MODELO.VARIAVEL(1)',
      'AUTOMACAO_LIVRE.ALTERAR_PAINEL.MODELO.VARIAVEL(2)',
    ]);
  });

  it('modelo de utilidade não avisa custo; o de propaganda avisa', () => {
    const escolha = {
      modelValue: { nome: 'pedido_saiu', idioma: 'pt_BR', variaveis: [[], []] },
    };
    expect(montar(escolha).find('[data-modelo-custo]').exists()).toBe(false);

    caixas.value = [
      {
        ...OFICIAL,
        message_templates: [{ ...APROVADO, category: 'MARKETING' }],
      },
    ];
    expect(montar(escolha).find('[data-modelo-custo]').text()).toBe(
      'AUTOMACAO_LIVRE.CAMPANHA.CUSTO_PROPAGANDA'
    );
  });

  it('corpo diferente em outra caixa: avisa', () => {
    caixas.value = [
      { ...OFICIAL, message_templates: [APROVADO] },
      {
        ...OFICIAL,
        message_templates: [
          {
            ...APROVADO,
            components: [{ type: 'BODY', text: 'Olá {{1}} {{2}}' }],
          },
        ],
      },
    ];
    const wrapper = montar({
      modelValue: { nome: 'pedido_saiu', idioma: 'pt_BR', variaveis: [[], []] },
    });

    expect(wrapper.find('[data-modelo-divergente]').exists()).toBe(true);
  });

  it('o modelo passou a pedir mais variáveis: avisa, e editar completa a lista', async () => {
    const wrapper = montar({
      modelValue: {
        nome: 'pedido_saiu',
        idioma: 'pt_BR',
        variaveis: [['Ana']],
      },
    });

    expect(wrapper.find('[data-modelo-mudou]').text()).toBe(
      'AUTOMACAO_LIVRE.ALTERAR_PAINEL.MODELO.MUDOU(2)'
    );
    await wrapper
      .findAllComponents(LivreTexto)[1]
      .vm.$emit('update:modelValue', ['nº 42']);

    expect(wrapper.emitted('update:modelValue')[0][0].variaveis).toEqual([
      ['Ana'],
      ['nº 42'],
    ]);
  });

  it('modelo salvo que não serve mais: avisa', () => {
    caixas.value = [
      { ...OFICIAL, message_templates: [{ ...APROVADO, status: 'REJECTED' }] },
    ];
    const wrapper = montar({
      modelValue: { nome: 'pedido_saiu', idioma: 'pt_BR', variaveis: [[], []] },
    });

    expect(wrapper.find('[data-sem-modelos]').exists()).toBe(true);
  });

  it('sem caixa oficial com modelo: diz onde criar', () => {
    caixas.value = [];
    expect(montar().find('[data-sem-modelos]').exists()).toBe(true);
  });
});
