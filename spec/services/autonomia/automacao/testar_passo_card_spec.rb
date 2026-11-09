require 'rails_helper'

# #2679 no "Testar este passo": com `le: card`, o card da conversa vai à IA só se quem pede o vê (Crm::CardPolicy), o
# valor só com a chave dele (#2597) e o anúncio de origem nunca, como no passo de verdade (Funções, C2).
RSpec.describe Autonomia::Automacao::TestarPasso, :automacao_motor do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [admin]) }
  let(:contato) { account.contacts.create!(name: 'Rose', phone_number: '+5511987654321') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contato) }
  let(:corpos) { [] }
  let(:resumir) { { 'id' => 'p1', 'tipo' => 'resumir', 'le' => %w[card mensagens_recentes], 'linhas' => 2, 'destino' => 'nota' } }

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      payload = { id: "resp_#{corpos.size}", output_text: { resumo: 'Festa Frozen.' }.to_json, usage: { input_tokens: 10, output_tokens: 5 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
    funil, etapa = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: funil, stage: etapa, inbox: inbox, contact: contato, primary_conversation: conversa,
                              title: 'Festa da Lara', custom_attributes: { 'tema' => 'Frozen' })
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, content: 'Quero mudar o tema')
  end

  after { Current.reset }

  def testar(gatilho: 'conversa.resolvida', quem: admin, ligada_por: nil)
    receita = { 'gatilho' => { 'tipo' => gatilho }, 'passos' => [resumir] }
    described_class.new(receita: receita, passo_id: 'p1', conta: account, account_user: quem.account_users.first,
                        conversa_id: conversa.display_id, ligada_por: ligada_por).resultado(com_valores: false)[:conversa]
  end

  def entrada = corpos.sole['input'].to_json

  it 'quem pede vê o card: ele vai à IA, com os campos', :aggregate_failures do
    expect(testar[:resultado]).to eq(texto: 'Festa Frozen.')
    expect(corpos.sole['input'].to_json).to include('Festa da Lara', 'Frozen', 'Quero mudar o tema')
  end

  it 'quem pede não vê o card: a IA lê o resto, sem ele', :aggregate_failures do
    allow(Autonomia::Automacao::ComIa).to receive(:ve_o_card?).and_return(false)

    testar

    expect(corpos.sole['input'].to_json).to include('Quero mudar o tema')
    expect(corpos.sole['input'].to_json).not_to include('Festa da Lara')
  end

  # #2780: o teste leva o valor da venda só se quem testa e quem ligou podem, e nunca mais que a execução: na automação
  # de conversa, o passo que escreve não o leva.
  describe 'o valor da venda' do
    let(:agente) { create(:user, account: account, role: :agent) }

    before { account.crm_cards.sole.update!(value_cents: 1_234_500) }

    it 'na automação de conversa, o passo que escreve não leva o valor' do
      testar

      expect(entrada).to include('Festa da Lara')
      expect(entrada).not_to include('12345')
    end

    it 'na automação de card, quem testa e pode ver leva o valor' do
      testar(gatilho: 'card.ganho')

      expect(entrada).to include('12345')
    end

    it 'na automação de card, quem testa sem permissão não leva o valor' do
      allow(Crm::ValorDeVenda).to receive(:ve?).and_return(false)

      testar(gatilho: 'card.ganho')

      expect(entrada).not_to include('12345')
    end

    it 'na automação de card, quem ligou sem permissão também tira o valor do teste', :aggregate_failures do
      allow(Crm::ValorDeVenda).to receive(:ve?) { |account_user| account_user&.user_id == admin.id }

      testar(gatilho: 'card.ganho', ligada_por: agente)
      expect(entrada).not_to include('12345')

      corpos.clear
      testar(gatilho: 'card.ganho', ligada_por: admin)
      expect(entrada).to include('12345')
    end
  end
end
