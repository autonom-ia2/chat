require 'rails_helper'

RSpec.describe Integrations::Hook do
  let(:account) { create(:account) }

  before { allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true) }

  def build_hook(settings)
    build(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: settings)
  end

  describe 'CRM Kanban AI hook' do
    it 'turns the AI on when the key is connected' do
      hook = build_hook({ 'api_key' => 'sk-valida' })

      expect(hook).to be_valid
      expect(hook.settings['enabled']).to be true
    end

    it 'keeps the AI on for the credential resolver' do
      hook = build_hook({ 'api_key' => 'sk-valida' })
      hook.save!

      credential = Crm::Ai::CredentialResolver.new(account: account.reload).resolve

      expect(credential).to include(api_key: 'sk-valida', source: :hook)
    end

    it 'respects an explicit request to turn the AI off' do
      hook = build_hook({ 'api_key' => 'sk-valida', 'enabled' => false })

      expect(hook).to be_valid
      expect(hook.settings['enabled']).to be false
    end

    it 'keeps the AI off on later updates instead of forcing it back on' do
      hook = build_hook({ 'api_key' => 'sk-valida' })
      hook.save!
      hook.update!(settings: { 'api_key' => 'sk-valida', 'enabled' => false })

      hook.update!(settings: hook.settings.merge('api_key' => 'sk-outra'))

      expect(hook.reload.settings['enabled']).to be false
      expect(Crm::Ai::CredentialResolver.new(account: account.reload).resolve).to be_nil
    end

    it 'refuses a key the OpenAI account rejects' do
      allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(false)

      hook = build_hook({ 'api_key' => 'sk-recusada' })

      expect(hook).not_to be_valid
      expect(hook.errors[:base]).to include(I18n.t('errors.openai.invalid_api_key'))
    end

    it 'does not offer the AI on/off switch in the connect form' do
      form_fields = Integrations::App.find(id: 'crm_kanban_ai').params[:settings_form_schema].pluck('name')

      expect(form_fields).to contain_exactly('api_key', 'api_base')
    end
  end
end
