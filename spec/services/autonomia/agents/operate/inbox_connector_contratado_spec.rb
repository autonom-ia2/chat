require 'rails_helper'

# #3211 (Tarefa 22) — o contratado só vai para uma caixa depois que o acesso à seguradora foi conferido (`ok`).
RSpec.describe Autonomia::Agents::Operate::InboxConnector do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  # Nasce como o Contratar o cria: rascunho e parado, com a marca do catálogo.
  let(:contratado) do
    Autonomia::Agents::Agent.new(
      account: account, name: 'Contratado', agent_type: 'sdr', status: :draft, enabled: false, mode: :guided,
      instruction: 'Atenda.',
      config: { Autonomia::Agents::Contratados::MARCA => { 'modelo' => 'seguro_viagem_universal' } }
    ).tap { |agente| agente.save!(context: %i[create ativacao]) }
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before { enable_test_encryption! }

  context 'without acesso conferido' do
    it 'recusa o ativar e deixa o agente em rascunho, sem vínculo' do
      result = described_class.new(agent: contratado, inbox: inbox, ativar: true).perform(connect: true)

      expect(result.status).to eq(:error)
      expect(result.error).to eq(:acesso_da_seguradora_pendente)
      expect(Autonomia::Agents::AgentInbox.where(agent_id: contratado.id)).to be_empty
      expect(contratado.reload.status).to eq('draft')
    end

    it 'recusa também quando o acesso existe mas não está ok' do
      Autonomia::Agents::AcessoDaSeguradora.create!(agent: contratado, account: account, login: 'corretor.teste',
                                                    senha: 's3nha-teste', estado: 'recusado')

      result = described_class.new(agent: contratado, inbox: inbox, ativar: true).perform(connect: true)

      expect(result.error).to eq(:acesso_da_seguradora_pendente)
      expect(Autonomia::Agents::AgentInbox.where(agent_id: contratado.id)).to be_empty
    end
  end

  context 'with acesso ok' do
    before do
      Autonomia::Agents::AcessoDaSeguradora.create!(agent: contratado, account: account, login: 'corretor.teste',
                                                    senha: 's3nha-teste', estado: 'ok')
    end

    it 'liga a caixa e tira o agente do rascunho' do
      result = described_class.new(agent: contratado, inbox: inbox, ativar: true).perform(connect: true)

      expect(result).to be_success
      expect(Autonomia::Agents::AgentInbox.where(agent_id: contratado.id, inbox_id: inbox.id)).to exist
      expect(contratado.reload).to have_attributes(status: 'active', enabled: true)
    end
  end

  it 'agente comum segue ligando sem acesso nenhum' do
    comum = Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :draft,
                                             enabled: false, instruction: 'Atenda.')

    result = described_class.new(agent: comum, inbox: inbox, ativar: true).perform(connect: true)

    expect(result).to be_success
    expect(comum.reload.status).to eq('active')
  end
end
