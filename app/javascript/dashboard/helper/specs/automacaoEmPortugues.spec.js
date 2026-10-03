import { createI18n } from 'vue-i18n';
import automation from 'dashboard/i18n/locale/pt_BR/automation.json';
import crm from 'dashboard/i18n/locale/pt_BR/crm.json';
import {
  descreverAutomacao,
  nomeDaAcao,
} from 'dashboard/helper/automacaoEmPortugues';

// #859 — a frase que o corretor lê na lista. Usa os textos reais em português:
// se alguém renomear uma chave, a frase quebra aqui, não na tela.
const { t } = createI18n({
  legacy: false,
  locale: 'pt_BR',
  messages: { pt_BR: { ...automation, ...crm } },
}).global;

const nomes = {
  inboxes: { 3: 'Comercial' },
  agentes: { 7: 'Ana' },
  times: { 2: 'Sinistros' },
  etapas: { 11: 'Prospecção › Novo' },
};

const regra = (extra = {}) => ({
  event_name: 'message_created',
  conditions: [],
  actions: [],
  ...extra,
});

describe('descreverAutomacao', () => {
  it('escreve quando, se e então com os nomes da conta', () => {
    const resultado = descreverAutomacao(
      regra({
        conditions: [
          {
            attribute_key: 'inbox_id',
            filter_operator: 'equal_to',
            values: [3],
            query_operator: 'AND',
          },
          {
            attribute_key: 'content',
            filter_operator: 'contains',
            values: ['sinistro'],
            query_operator: null,
          },
        ],
        actions: [
          { action_name: 'add_label', action_params: ['sinistro'] },
          { action_name: 'assign_team', action_params: [2] },
        ],
      }),
      { t, nomes }
    );

    expect(resultado.quando).toBe('Quando chega uma mensagem');
    expect(resultado.se.map(item => item.texto)).toEqual([
      'Caixa de Entrada é Comercial',
      'Conteúdo da mensagem contém sinistro',
    ]);
    expect(resultado.entao).toEqual([
      'Adicionar uma Etiqueta: sinistro',
      'Atribuir um Time: Sinistros',
    ]);
    expect(resultado.frase).toBe(
      'Quando chega uma mensagem, se Caixa de Entrada é Comercial e Conteúdo da mensagem contém sinistro → Adicionar uma Etiqueta: sinistro; Atribuir um Time: Sinistros'
    );
  });

  it('liga as condições com "ou" quando a regra pede', () => {
    const { frase } = descreverAutomacao(
      regra({
        event_name: 'conversation_created',
        conditions: [
          {
            attribute_key: 'status',
            filter_operator: 'equal_to',
            values: ['open'],
            query_operator: 'OR',
          },
          {
            attribute_key: 'priority',
            filter_operator: 'equal_to',
            values: ['urgent'],
            query_operator: null,
          },
        ],
        actions: [{ action_name: 'resolve_conversation', action_params: [] }],
      }),
      { t, nomes }
    );

    expect(frase).toBe(
      'Quando uma conversa nova começa, se Status é aberta ou Prioridade é Urgente → Resolver Conversa'
    );
  });

  it('sem condição, escreve só quando e então', () => {
    const { frase, se } = descreverAutomacao(
      regra({
        event_name: 'conversation_resolved',
        actions: [
          {
            action_name: 'send_message',
            action_params: ['Obrigado pelo contato!'],
          },
        ],
      }),
      { t, nomes }
    );

    expect(se).toEqual([]);
    expect(frase).toBe(
      'Quando uma conversa é resolvida → Enviar Mensagem: “Obrigado pelo contato!”'
    );
  });

  it('descreve espera, campo preenchido, mudança de valor e etapa do CRM', () => {
    const resultado = descreverAutomacao(
      regra({
        event_name: 'conversation_updated',
        execution_delay: 120,
        conditions: [
          {
            attribute_key: 'assignee_id',
            filter_operator: 'is_not_present',
            values: [],
            query_operator: 'AND',
          },
          {
            attribute_key: 'status',
            filter_operator: 'attribute_changed',
            values: { from: ['open'], to: ['pending'] },
            query_operator: null,
          },
        ],
        actions: [
          { action_name: 'crm_create_card', action_params: [11] },
          { action_name: 'assign_agent', action_params: [7] },
        ],
      }),
      { t, nomes }
    );

    expect(resultado.quando).toBe('Quando uma conversa muda e passam 2 horas');
    expect(resultado.se.map(item => item.texto)).toEqual([
      'Agente atribuído está vazio',
      'Status muda de aberta para pendente',
    ]);
    expect(resultado.entao).toEqual([
      'Criar card no CRM: Prospecção › Novo',
      'Atribuir ao Agente: Ana',
    ]);
  });

  it('não esconde o que não reconhece: id sem nome e ação nova', () => {
    const { entao } = descreverAutomacao(
      regra({
        actions: [
          { action_name: 'assign_team', action_params: [99] },
          { action_name: 'acao_que_ainda_nao_existe', action_params: [] },
        ],
      }),
      { t, nomes }
    );

    expect(entao).toEqual([
      'Atribuir um Time: nº 99',
      'um passo que esta tela ainda não sabe descrever',
    ]);
  });

  // Revisão de integração (#858 x #859): o passo do Decisor aparecia como
  // "um passo que esta tela ainda não sabe descrever".
  it('descreve o passo do Decisor com o nome e a resposta que segue', () => {
    const { entao } = descreverAutomacao(
      regra({
        actions: [
          { action_name: 'perguntar_ao_decisor', action_params: [12, 'sim'] },
          { action_name: 'add_label', action_params: ['lead'] },
        ],
      }),
      {
        t,
        nomes: {
          ...nomes,
          decisores: {
            12: {
              nome: 'É lead?',
              respostas: [
                { chave: 'sim', descricao: 'Pede cotação de seguro' },
                { chave: 'nao', descricao: 'Newsletter' },
              ],
            },
          },
        },
      }
    );

    expect(entao).toEqual([
      'Pergunta ao Decisor É lead?: segue se a resposta for “sim” (Pede cotação de seguro)',
      'Adicionar uma Etiqueta: lead',
    ]);
  });

  it('Decisor que a tela não carregou aparece pelo número', () => {
    const { entao } = descreverAutomacao(
      regra({
        actions: [
          { action_name: 'perguntar_ao_decisor', action_params: [99, 'nao'] },
        ],
      }),
      { t, nomes }
    );

    expect(entao).toEqual([
      'Pergunta ao Decisor #99: segue se a resposta for “nao”',
    ]);
  });
});

describe('nomeDaAcao', () => {
  it('usa o mesmo rótulo do modo manual', () => {
    expect(nomeDaAcao('resolve_conversation', t)).toBe('Resolver Conversa');
    expect(nomeDaAcao('perguntar_ao_decisor', t)).toBe('Perguntar ao Decisor');
    expect(nomeDaAcao('qualquer_coisa', t)).toBe(
      'um passo que esta tela ainda não sabe descrever'
    );
  });
});
