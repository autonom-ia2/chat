import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AgenteCartao from '../components/AgenteCartao.vue';
import AgenteStatus from '../components/AgenteStatus.vue';
import CelularConversa from '../components/CelularConversa.vue';
import { ESTADO } from '../utils/estadoDoAgente';

// Cópia real em pt_BR (protótipo jornada.html): plural, números em negrito e {nome} neutro.
withFullI18n('pt_BR');

const agente = extra => ({
  id: 5,
  name: 'Duda',
  status: 'active',
  enabled: true,
  agent_type: 'support',
  actuation: 'external',
  channels_count: 1,
  ...extra,
});

const montar = props =>
  mount(AgenteCartao, {
    props: {
      agente: agente(),
      numeros: { respondidas: 12, passadas: 3 },
      canais: [{ inbox_id: 10, name: 'WhatsApp do Centro' }],
      href: '/app/agentes/5',
      ...props,
    },
  });

describe('cópia da lista em pt_BR', () => {
  it('writes the week line with bold numbers', () => {
    const semana = montar().get('[data-semana]');
    expect(semana.text()).toContain('Esta semana: 12 conversas respondidas');
    expect(semana.text()).toContain('3 passadas para alguém da equipe');
    expect(semana.findAll('b').map(b => b.text())).toEqual(['12', '3']);
  });

  it('uses the singular for one conversation', () => {
    const semana = montar({ numeros: { respondidas: 1, passadas: 1 } }).get(
      '[data-semana]'
    );
    expect(semana.text()).toContain('Esta semana: 1 conversa respondida');
    expect(semana.text()).toContain('1 passada para alguém da equipe');
  });

  it('names the inbox, or counts them without the name', () => {
    expect(montar().get('[data-onde]').text()).toBe(
      'Responde no WhatsApp do Centro'
    );
    expect(montar({ canais: null }).get('[data-onde]').text()).toBe(
      'Responde em 1 canal'
    );
    expect(
      montar({ agente: agente({ channels_count: 3 }), canais: null })
        .get('[data-onde]')
        .text()
    ).toBe('Responde em 3 canais');
  });

  it('uses the new state words, never "Ligar"', () => {
    const textos = Object.values(ESTADO).map(estado =>
      mount(AgenteStatus, { props: { estado } }).text()
    );
    expect(textos).toEqual([
      'Atendendo',
      'Na equipe',
      'Ajudando',
      'Parado',
      'Falta terminar',
      'Cotação',
    ]);
  });
});

describe('cópia do celular em pt_BR', () => {
  it('names who speaks in each bubble for screen readers', () => {
    const wrapper = mount(CelularConversa, {
      props: {
        mensagens: [
          { de: 'cliente', texto: 'Vocês abrem no sábado?' },
          { de: 'agente', texto: 'Abrimos sim.', usou: ['tabela.pdf'] },
        ],
      },
    });
    const nomes = wrapper.findAll('[data-balao] .sr-only').map(n => n.text());
    expect(nomes).toEqual(['Cliente:', 'Agente:']);
    expect(wrapper.get('[data-usou]').text()).toBe('Usou: tabela');
  });

  // Piloto conta 16: "usou: hub2you_base_…_v1.pdf" vazava do balão no celular de teste.
  it('says "Usou:" with a long name without extension, inside the bubble', () => {
    const arquivo = 'hub2you_base_conhecimento_agente_vendas_v1.pdf';
    const wrapper = mount(CelularConversa, {
      props: { mensagens: [{ de: 'agente', texto: 'Oi', usou: [arquivo] }] },
    });
    const usou = wrapper.get('[data-usou]');
    expect(usou.text()).toBe(
      'Usou: hub2you_base_conhecimento_agente_vendas_v1'
    );
    expect(usou.attributes('title')).toBe(arquivo);
  });
});
