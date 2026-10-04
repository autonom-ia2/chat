require 'rails_helper'

# O registro de diagnóstico de um pedido ao Guia (#861): o que ele leu, chamou e
# decidiu, para o time investigar um relato. Guarda o mínimo — nunca o valor que
# a pessoa mandou gravar, que pode ser telefone ou credencial.
RSpec.describe Autonomia::Guide::Registro do
  subject(:registro) { described_class.new }

  let(:conta) { create(:account) }

  def chamada(nome, args)
    { 'name' => nome, 'arguments' => args.to_json }
  end

  describe '#registrar_chamada' do
    it 'guarda o recurso lido, mas nunca o corpo de uma escrita', :aggregate_failures do
      registro.registrar_chamada(chamada('ler_da_conta', recurso: 'inboxes', pagina: '2'), '[{"id":1}]', 420)
      registro.registrar_chamada(
        chamada('executar_acao', acao: 'PATCH contacts/7', descricao: 'Atualizei o telefone.',
                                 corpo_json: '{"phone_number":"+5511999998888","api_key":"segredo-123"}'),
        'Pronto.', 300
      )

      leitura, escrita = registro.chamadas
      expect(leitura).to include('ferramenta' => 'ler_da_conta', 'args' => { 'recurso' => 'inboxes', 'pagina' => '2' },
                                 'ms' => 420, 'saida_chars' => 10, 'dados' => true)
      expect(escrita['args']).to eq('acao' => 'PATCH contacts/7', 'descricao' => 'Atualizei o telefone.')
      expect(escrita['omitidos']).to eq(['corpo_json'])
      expect(registro.diagnostico.to_json).not_to include('5511999998888', 'segredo-123')
    end

    it 'de uma página da internet guarda só o domínio' do
      registro.registrar_chamada(chamada('ler_pagina', url: 'https://exemplo.com.br/cliente?cpf=12345678900'), 'texto', 10)

      expect(registro.chamadas.first['args']).to eq('dominio' => 'exemplo.com.br')
    end

    it 'da recusa guarda o código, sem o detalhe' do
      registro.registrar_chamada(chamada('ler_da_conta', recurso: 'x'), '{"error":"tool_not_available: Maria 1199"}', 5)

      expect(registro.chamadas.first['recusa']).to eq('tool_not_available')
    end

    it 'de ferramenta desconhecida guarda só os nomes dos argumentos', :aggregate_failures do
      registro.registrar_chamada(chamada('especialista_auto', pedido: 'placa ABC1D23'), 'ok', 5)

      expect(registro.chamadas.first['args']).to eq({})
      expect(registro.chamadas.first['omitidos']).to eq(['pedido'])
    end
  end

  describe '#ativo' do
    it 'soma o custo e os tokens de cada ida ao modelo pela notificação', :aggregate_failures do
      registro.ativo do
        Crm::Ai::UsageRecorder.record(account: conta, feature: 'guia', model: 'gpt-5.6-sol', reasoning_effort: 'low',
                                      usage: { input_tokens: 100, output_tokens: 20,
                                               input_tokens_details: { cached_tokens: 40 } })
        Crm::Ai::UsageRecorder.record(account: conta, feature: 'guia', model: 'gpt-5.6-sol', reasoning_effort: 'low',
                                      usage: { input_tokens: 50, output_tokens: 10 })
      end

      diagnostico = registro.diagnostico
      eventos = Crm::AiUsageEvent.where(account: conta)
      expect(diagnostico['rodadas']).to eq(2)
      expect(diagnostico['modelo']).to eq('gpt-5.6-sol')
      expect(diagnostico['tokens']).to eq('in' => 150, 'cached' => 40, 'out' => 30)
      expect(diagnostico['custo_usd']).to be_within(1e-6).of(eventos.sum(:cost_estimate).to_f)
      expect(diagnostico['ms']).to be_a(Integer)
    end

    it 'não soma o custo de outra thread' do
      registro.ativo do
        Thread.new do
          Crm::Ai::UsageRecorder.record(account: conta, feature: 'guia', model: 'gpt-5.6-sol', usage: { input_tokens: 10 })
        end.join
      end

      expect(registro.diagnostico['rodadas']).to eq(0)
    end

    it 'não soma o que acontece depois do turno' do
      registro.ativo { nil }
      Crm::Ai::UsageRecorder.record(account: conta, feature: 'guia', model: 'gpt-5.6-sol', usage: { input_tokens: 10 })

      expect(registro.diagnostico['rodadas']).to eq(0)
    end
  end

  describe '#decidir' do
    it 'guarda o texto retido cortado, e só quando foi retido', :aggregate_failures do
      registro.decidir(fluxos: [{ id: 12, content: 'o texto do fluxo', source: 'Criar etiqueta' }], retido: true,
                       resposta_retida: 'x' * 3_000, confianca: 0.3)

      diagnostico = registro.diagnostico
      expect(diagnostico['fluxos']).to eq([{ 'id' => 12, 'titulo' => 'Criar etiqueta' }])
      expect(diagnostico['resposta_retida'].size).to eq(2_000)
      expect(diagnostico.to_json).not_to include('o texto do fluxo')

      registro.decidir(retido: false, resposta_retida: 'não guarda')
      expect(registro.diagnostico['resposta_retida']).to be_nil
    end
  end
end
