require 'rails_helper'

RSpec.describe Autonomia::Prospecting::AiCredential do
  let(:account) { create(:account) }
  let(:credential) { described_class.new(account: account) }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').first_or_create!(value: 'chave-do-sistema')
  end

  def create_kanban_hook(settings)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: settings)
  end

  it 'devolve vazio sem hook crm_kanban_ai, mesmo com CAPTAIN_OPEN_AI_API_KEY na instalação' do
    expect(credential.resolve).to be_nil
    expect(credential).not_to be_configured
    expect(Crm::Ai::CredentialResolver.new(account: account).resolve).to include(source: :system)
  end

  it 'devolve vazio com a IA do hook desligada' do
    create_kanban_hook({ 'api_key' => 'chave-da-conta', 'enabled' => false })

    expect(credential.resolve).to be_nil
  end

  it 'devolve vazio com o hook sem api_key' do
    # O model não deixa gravar hook sem chave; o dado antigo no banco pode estar assim, por isso o update_columns.
    hook = create_kanban_hook({ 'api_key' => 'chave-da-conta' })
    hook.update_columns(settings: { 'api_key' => '', 'api_base' => 'https://proxy.example.com' }) # rubocop:disable Rails/SkipsModelValidations

    expect(credential.resolve).to be_nil
  end

  it 'devolve vazio com o hook desativado' do
    create_kanban_hook({ 'api_key' => 'chave-da-conta' }).update!(status: :disabled)

    expect(credential.resolve).to be_nil
  end

  it 'usa a chave e o endereço do hook da conta' do
    create_kanban_hook({ 'api_key' => 'chave-da-conta', 'api_base' => 'https://proxy.example.com' })

    expect(credential.resolve).to eq(api_key: 'chave-da-conta', api_base: 'https://proxy.example.com', source: :hook)
    expect(credential).to be_configured
  end

  it 'usa o endereço da OpenAI quando o hook não traz api_base' do
    create_kanban_hook({ 'api_key' => 'chave-da-conta' })

    expect(credential.resolve).to eq(api_key: 'chave-da-conta', api_base: 'https://api.openai.com', source: :hook)
  end

  it 'não lê a chave de outra conta' do
    create(:integrations_hook, account: create(:account), app_id: 'crm_kanban_ai', hook_type: :account,
                               settings: { 'api_key' => 'chave-da-outra' })

    expect(credential.resolve).to be_nil
  end
end
