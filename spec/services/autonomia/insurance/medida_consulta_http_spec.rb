require 'rails_helper'

# #1430: uma execução de ferramenta HTTP com o slug de uma nativa (linha antiga, de antes da validação do slug) não
# entra na medida da cotação nem na memória do resultado da cotação.
RSpec.describe Autonomia::Insurance::Medida do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:slug) { Autonomia::Agents::Tools::Native::InsuranceQuote.slug }

  def execucao(ferramenta_id)
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: slug, arguments: {},
                                     scope: { conversation_id: conversation.id, autonomia_agent_tool_id: ferramenta_id,
                                              faixa: ferramenta_id ? 'consulta_http' : 'auto' })
  end

  it 'a medida conta so as nativas' do
    nativa = execucao(nil)
    execucao(999)

    medida = described_class.new(inicio: 1.day.ago.to_date.to_s, fim: 1.day.from_now.to_date.to_s, conta: account)

    expect(medida.send(:escopo).pluck(:id)).to eq([nativa.id])
  end

  it 'a memoria nao le a consulta HTTP como cotacao' do
    expect(Crm::Memoria::DaFerramenta.leitura(execucao(999))).to be_nil
  end
end
