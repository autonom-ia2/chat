require 'rails_helper'

RSpec.describe Autonomia::Prospecting::Setting do
  let(:setting) { described_class.for_account(create(:account)) }

  describe '#search_country' do
    it 'é Brasil quando a conta nunca escolheu' do
      expect(setting.search_country).to eq('BR')
    end

    it 'guarda o país escolhido no metadata, em maiúsculas' do
      setting.update!(search_country: 'pt')

      expect(setting.reload.search_country).to eq('PT')
      expect(setting.metadata['search_country']).to eq('PT')
    end

    it 'recusa país fora da lista' do
      setting.search_country = 'ZZ'

      expect(setting).not_to be_valid
      expect(setting.errors.full_messages).to eq(['Escolha um país da lista.'])
    end

    it 'cai para o Brasil e registra no log quando o valor gravado é inválido' do
      # Dado legado: a validação atual não deixaria gravar este valor.
      setting.update_columns(metadata: { 'search_country' => 'ZZ' }) # rubocop:disable Rails/SkipsModelValidations
      allow(Rails.logger).to receive(:warn)

      expect(setting.reload.search_country).to eq('BR')
      expect(Rails.logger).to have_received(:warn).with(a_string_including("account_id=#{setting.account_id}", 'search_country=ZZ'))
    end
  end
end
