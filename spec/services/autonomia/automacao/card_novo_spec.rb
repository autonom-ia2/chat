require 'rails_helper'

# A criação comum do card de automação (#2414 F1.4 e G4): a pergunta "já tem card" roda dentro da trava, para duas
# execuções juntas não criarem dois cards. O CardNaEtapa (Regras) e o PassoDeCard criam por aqui.
RSpec.describe Autonomia::Automacao::CardNovo do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:etapa) { create_crm_pipeline(account: account, user: admin).last }
  let(:conversa) { create(:conversation, account: account).reload }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  it 'pergunta "já tem card" dentro da trava da conversa, e não cria quando já tem', :aggregate_failures do
    travada = false
    allow(conversa).to receive(:with_lock).and_wrap_original do |original, &bloco|
      original.call do
        travada = true
        bloco.call
      ensure
        travada = false
      end
    end
    perguntas = []

    card = described_class.new(stage: etapa, conversation: conversa).criar do
      perguntas << travada
      true
    end

    expect(card).to be_nil
    expect(perguntas).to eq([true])
    expect(Crm::Card.count).to eq(0)
  end

  it 'sem conversa, trava o contato e cria o card só dele, com o nome', :aggregate_failures do
    contato = create(:contact, account: account, name: 'Lia')
    allow(contato).to receive(:with_lock).and_call_original

    card = described_class.new(stage: etapa, contact: contato).criar { false }

    expect(contato).to have_received(:with_lock)
    expect(card).to have_attributes(contact_id: contato.id, conversation_id: nil, title: 'Lia', stage_id: etapa.id)
  end
end
