require 'rails_helper'

# chat#1489: modelo recuperado do celular com arquivo no cabeçalho. O texto vai ao histórico com uma linha avisando que
# o arquivo não foi lido, para a IA não responder como se tivesse visto a imagem.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: create(:agent_bot, account: account))
  end

  def recebida(texto, atributos = {})
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: texto, content_attributes: atributos)
  end

  def historico
    described_class.new(conversation: conversation, agent_inbox: agent_inbox).send(:history).pluck(:content)
  end

  it 'imagem no cabeçalho: o texto e a linha de que a imagem não foi lida' do
    recebida('Sua fatura está disponível.', 'hybrid_recovery' => 'recovered', 'hybrid_recovery_header' => 'image')

    expect(historico).to eq(["Sua fatura está disponível.\n[a mensagem tinha uma imagem que não foi lida]"])
  end

  it 'outro arquivo no cabeçalho: a linha do arquivo' do
    recebida('Contrato anexo.', 'hybrid_recovery_header' => 'media')

    expect(historico).to eq(["Contrato anexo.\n[a mensagem tinha um arquivo que não foi lido]"])
  end

  it 'mensagem comum: só o texto, como antes' do
    recebida('Oi')

    expect(historico).to eq(['Oi'])
  end
end
