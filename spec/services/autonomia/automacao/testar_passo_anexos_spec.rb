require 'rails_helper'

# G20 (#2669) no "Testar este passo": com `le: anexos`, o teste manda à IA os mesmos anexos que a execução, e o anexo que
# não pode ir à IA vira o motivo da conversa, sem chamá-la.
RSpec.describe Autonomia::Automacao::TestarPasso, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:corpos) { [] }
  let(:resumir) { { 'id' => 'p1', 'tipo' => 'resumir', 'le' => %w[mensagens_recentes anexos], 'linhas' => 2, 'destino' => 'nota' } }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      payload = { id: "resp_#{corpos.size}", output_text: { resumo: 'Mandou o currículo.' }.to_json, usage: { input_tokens: 10, output_tokens: 5 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  after { Current.reset }

  def anexar(arquivo, tipo, content_type)
    mensagem = create(:message, conversation: conversa, account: account, message_type: :incoming, content: nil)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: tipo)
    anexo.file.attach(io: Rails.root.join("spec/assets/#{arquivo}").open, filename: arquivo, content_type: content_type)
    anexo.save!
  end

  def testar(definicao)
    described_class.new(receita: definicao.versao_ativa.receita, passo_id: 'p1', conta: account, account_user: admin.account_users.first,
                        conversa_id: conversa.display_id).resultado(com_valores: false)[:conversa]
  end

  it 'o teste manda à IA os mesmos anexos que a execução', :aggregate_failures do
    anexar('sample.pdf', :file, 'application/pdf')
    definicao = automacao_ligada(account, admin, [resumir])

    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }
    teste = testar(definicao)

    expect(corpos.size).to eq(2)
    expect(corpos.last.slice('instructions', 'input')).to eq(corpos.first.slice('instructions', 'input'))
    expect(teste[:resultado]).to eq(texto: 'Mandou o currículo.')
  end

  it 'o anexo que não pode ir à IA vira o motivo da conversa, sem chamá-la', :aggregate_failures do
    anexar('contacts.csv', :file, 'text/csv')

    expect(testar(automacao_ligada(account, admin, [resumir]))).to include(motivo: 'anexo_fora_do_formato')
    expect(corpos).to be_empty
  end
end
