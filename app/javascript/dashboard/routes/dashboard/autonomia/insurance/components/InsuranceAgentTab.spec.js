import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import InsuranceAgentTab from './InsuranceAgentTab.vue';

const api = vi.hoisted(() => ({
  getQuoteAgent: vi.fn(),
  createQuoteAgent: vi.fn(),
}));
vi.mock('dashboard/api/autonomiaInsurance', () => ({ default: api }));

const push = vi.hoisted(() => vi.fn());
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

// A ABA DEIXOU DE SER CARTAZ. Até 08/09/2026 o botão "Criar Agente de Cotação" só navegava para o
// construtor conversacional, e quem clicasse saía de lá com um agente `custom` sem ferramenta de
// cotação — igual a qualquer outro, e sem saber cotar.
//
// Estes exemplos travam que ela CRIA, que não deixa criar dois, e que a mensagem de erro é a do
// produto e não a do backend.
const criado = {
  id: 1,
  name: 'Mia',
  agent_type: 'insurance_quote',
  enabled: true,
  specialists: [{ slug: 'cotacao_auto', name: 'Cotação de automóvel' }],
};

// O `NextButton` recebe o rótulo por prop e não o expõe como texto do <button>; sem o stub não há
// como distinguir um botão do outro. E o i18n do vitest devolve a CHAVE, não a tradução — por isso
// as asserções falam em `INSURANCE.AGENT.…` e não em português. Quem julga a cópia é o
// `copy.spec.js` da aba Conexões, que monta o i18n completo.
const montar = async () => {
  const wrapper = mount(InsuranceAgentTab, {
    global: {
      stubs: {
        NextButton: {
          props: ['label', 'disabled', 'isLoading'],
          template:
            '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const botao = (wrapper, chave) =>
  wrapper.findAll('button').find(b => b.text().includes(chave));

const preencher = async wrapper => {
  await botao(wrapper, 'ACTIONS.CONFIGURE').trigger('click');
  const campos = wrapper.findAll('input');
  await campos[0].setValue('Mia');
  await campos[1].setValue('Corretora Exemplo');
  return campos;
};

describe('InsuranceAgentTab', () => {
  beforeEach(() => {
    Object.values(api).forEach(fn => fn.mockReset());
    push.mockReset();
    api.getQuoteAgent.mockResolvedValue({ data: { payload: null } });
  });

  it('nao mostra o formulario antes de alguem pedir', async () => {
    const wrapper = await montar();

    expect(wrapper.findAll('input')).toHaveLength(0);
    expect(botao(wrapper, 'ACTIONS.CONFIGURE')).toBeTruthy();
  });

  it('abre as quatro perguntas ao configurar', async () => {
    const wrapper = await montar();
    await botao(wrapper, 'ACTIONS.CONFIGURE').trigger('click');

    // Três campos de texto mais os dois botões de comportamento: quatro respostas.
    expect(wrapper.findAll('input')).toHaveLength(3);
    expect(wrapper.findAll('button[aria-pressed]')).toHaveLength(2);
  });

  // O backend recusa nome vazio. Deixar o clique disponível para receber um erro previsível é
  // atrito sem causa.
  it('so habilita criar com os dois nomes preenchidos', async () => {
    const wrapper = await montar();
    await botao(wrapper, 'ACTIONS.CONFIGURE').trigger('click');
    const criar = () => botao(wrapper, 'ACTIONS.SUBMIT');

    expect(criar().attributes('disabled')).toBeDefined();
    await wrapper.findAll('input')[0].setValue('Mia');
    expect(criar().attributes('disabled')).toBeDefined();
    await wrapper.findAll('input')[1].setValue('Corretora Exemplo');
    expect(criar().attributes('disabled')).toBeUndefined();
  });

  it('manda o que a corretora respondeu, e nada mais', async () => {
    api.createQuoteAgent.mockResolvedValue({ data: { payload: criado } });
    const wrapper = await montar();
    const campos = await preencher(wrapper);
    await campos[2].setValue('todo dia, das 08h às 20h');
    await wrapper.findAll('button[aria-pressed]')[1].trigger('click');
    await botao(wrapper, 'ACTIONS.SUBMIT').trigger('click');
    await flushPromises();

    expect(api.createQuoteAgent).toHaveBeenCalledWith({
      name: 'Mia',
      brokerName: 'Corretora Exemplo',
      businessHours: 'todo dia, das 08h às 20h',
      behavior: 'objetivo',
    });
  });

  it('fecha o formulario e mostra o agente com os ramos que ele cota', async () => {
    api.createQuoteAgent.mockResolvedValue({ data: { payload: criado } });
    const wrapper = await montar();
    await preencher(wrapper);
    await botao(wrapper, 'ACTIONS.SUBMIT').trigger('click');
    await flushPromises();

    expect(wrapper.findAll('input')).toHaveLength(0);
    // O nome do agente é interpolado direto no template e aparece; o dos ramos entra por
    // `t(..., { ramos })`, e o i18n do vitest não interpola — por isso o teste procura a chave.
    expect(wrapper.text()).toContain('Mia');
    expect(wrapper.text()).toContain('EXISTING.BRANCHES');
  });

  // Um por conta. Oferecer "criar" a quem já tem produziria o 409 na cara do usuário.
  it('nao oferece criar quando ja existe', async () => {
    api.getQuoteAgent.mockResolvedValue({ data: { payload: criado } });
    const wrapper = await montar();

    expect(botao(wrapper, 'ACTIONS.CONFIGURE')).toBeFalsy();
    expect(botao(wrapper, 'ACTIONS.OPEN_AGENT')).toBeTruthy();
    expect(wrapper.text()).toContain('Mia');
  });

  // 409 não é falha: alguém clicou duas vezes, ou já havia um. Mostrar erro sobre algo que a própria
  // tela pediu seria culpar o usuário pelo que o sistema já sabia.
  it('trata "ja existe" mostrando o que existe, sem erro', async () => {
    api.createQuoteAgent.mockRejectedValue({
      response: {
        status: 409,
        data: { payload: { ...criado, name: 'Clara' } },
      },
    });
    const wrapper = await montar();
    await preencher(wrapper);
    await botao(wrapper, 'ACTIONS.SUBMIT').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('Clara');
    expect(wrapper.findAll('input')).toHaveLength(0);
  });

  it('mostra a mensagem do produto quando o backend recusa o nome', async () => {
    api.createQuoteAgent.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'nome_invalido', detail: 'nome do agente vazio' },
      },
    });
    const wrapper = await montar();
    await preencher(wrapper);
    await botao(wrapper, 'ACTIONS.SUBMIT').trigger('click');
    await flushPromises();

    // O `detail` do backend serve no log; a tela fala a língua do produto.
    expect(wrapper.text()).toContain('ERRORS.NOME_INVALIDO');
    expect(wrapper.text()).not.toContain('nome do agente vazio');
  });

  // #380 (rodada 6): o horário com um marcador reservado dentro (`$nomeAgente`) é recusado pelo backend
  // com `horario_invalido`. Sem a linha própria ele cairia em GENERIC — «tente de novo em instantes»
  // para um erro que tentar de novo não resolve.
  it('mostra a mensagem do produto quando o backend recusa o horario', async () => {
    api.createQuoteAgent.mockRejectedValue({
      response: {
        status: 422,
        data: {
          error: 'horario_invalido',
          detail: 'horário contém um marcador reservado',
        },
      },
    });
    const wrapper = await montar();
    await preencher(wrapper);
    await botao(wrapper, 'ACTIONS.SUBMIT').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('ERRORS.HORARIO_INVALIDO');
    expect(wrapper.text()).not.toContain('ERRORS.GENERIC');
    expect(wrapper.text()).not.toContain('marcador reservado');
  });

  it('cai na mensagem geral quando o erro nao tem codigo conhecido', async () => {
    api.createQuoteAgent.mockRejectedValue({
      response: { status: 500, data: {} },
    });
    const wrapper = await montar();
    await preencher(wrapper);
    await botao(wrapper, 'ACTIONS.SUBMIT').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('ERRORS.GENERIC');
    // O formulário fica aberto: o usuário precisa poder tentar de novo sem redigitar.
    expect(wrapper.findAll('input')).toHaveLength(3);
  });
});
