require 'rails_helper'

# "COTAÇÃO FECHADA" COM DOIS SEGUROS NA CONVERSA (revisão da chat#608). A cotação que corria no começo do turno pode
# fechar enquanto a outra (auto ou residencial) continua. Aí "ainda está saindo" é verdade para a outra, e o sinal
# que manda a Lia dizer que terminou não pode sair. Dados sintéticos.
RSpec.describe Autonomia::Agents::ConferenciaDaFala do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:fala) { 'A cotação do carro continua correndo, já te aviso.' }

  def cotacao(faixa, criada:)
    Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: 'cotar_seguro', status: 'running', faixa: faixa,
                                       conversation_id: conversa.id, execution_key: SecureRandom.uuid,
                                       arguments: {}, handle: { 'quote_id' => 'q' }, created_at: criada)
  end

  def fecha(run)
    run.update!(status: 'done', handle: run.handle.merge('portal_fechado' => true))
  end

  def sinais
    no_inicio = described_class.cotacao_correndo(conversa.id)
    yield no_inicio
    described_class.new(conversa: conversa.id, cotacao_no_inicio: no_inicio).sinais(fala, ferramentas_no_turno: 0)
  end

  it 'com uma cotação só, a que fechou no turno dispara o sinal' do
    cotacao('auto', criada: 1.hour.ago)

    expect(sinais { |run| fecha(run) }).to include(:cotacao_fechada)
  end

  it 'com a outra ainda correndo, a que fechou no turno não dispara o sinal' do
    cotacao('auto', criada: 2.hours.ago)
    cotacao('residencial', criada: 1.hour.ago)

    expect(sinais { |run| fecha(run) }).not_to include(:cotacao_fechada)
  end
end
