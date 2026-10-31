require 'rails_helper'

# #1430: os eventos genéricos da ferramenta HTTP assíncrona. Os fatos vêm do que o job gravou na execução, não do
# catálogo das nativas, e nada do texto fala em cotação.
RSpec.describe Autonomia::Agents::Tools::Evento do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:tool) do
    Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Cotar seguro', slug: 'cotar_seguro',
                                    timeout_seconds: 60, endpoint_url: 'https://erp.exemplo.test/pedidos', param_schema: [])
  end
  let(:run) do
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: tool.slug, arguments: {},
                                     scope: { conversation_id: conversation.id, autonomia_agent_tool_id: tool.id, faixa: 'http' })
                              .tap { |r| r.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now) }
  end

  before do
    run.gravar_resultado!('{"status":"enviado"}')
    allow(Autonomia::Agents::Tools::Registry).to receive(:find).and_call_original
  end

  it 'os dois tipos sao da lista fechada e disparam pelo slot do fecho' do
    expect(described_class::TIPOS).to include('consulta_concluida', 'consulta_falhou')
    expect(described_class.disparar(run, 'consulta_concluida')).to be(true)
    expect(eventos_disparados(run)).to eq(['consulta_concluida'])
  end

  it 'os fatos sao o resultado gravado na execucao, sem passar pelo catalogo' do
    evento = described_class.new(run: run.reload, tipo: 'consulta_concluida')

    expect(evento.fatos).to eq('{"status":"enviado"}')
    expect(Autonomia::Agents::Tools::Registry).not_to have_received(:find)
  end

  it 'a nota do sistema nao fala em cotacao' do
    %w[consulta_concluida consulta_falhou].each do |tipo|
      nota = described_class.new(run: run.reload, tipo: tipo).nota_do_sistema

      expect(nota.downcase).not_to include('cotação', 'cotacao')
      expect(nota).to include('AVISO DO SISTEMA', described_class::DESCRICOES.fetch(tipo), '{"status":"enviado"}')
    end
  end

  it 'a descricao dos dois tipos e neutra' do
    described_class::DESCRICOES.values_at('consulta_concluida', 'consulta_falhou').each do |texto|
      expect(texto.downcase).not_to include('cota')
    end
  end
end
