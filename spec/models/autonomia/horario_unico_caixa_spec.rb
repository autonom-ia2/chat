require 'rails_helper'

# #1619: com a flag `horario_unico_caixa`, a caixa segue o fuso da conta; desligada, vale a coluna.
RSpec.describe Autonomia::HorarioUnicoCaixa do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:inbox) { create(:inbox, account: account) }

  before { inbox.update_column(:timezone, 'UTC') } # rubocop:disable Rails/SkipsModelValidations

  describe '.ligado?' do
    it 'follows the account flag and is false without an account' do
      expect(described_class.ligado?(account)).to be(false)
      account.enable_features!(described_class::FEATURE)
      expect(described_class.ligado?(account)).to be(true)
      expect(described_class.ligado?(nil)).to be(false)
    end
  end

  describe 'Inbox#timezone' do
    it 'returns the column while the flag is off' do
      expect(inbox.reload.timezone).to eq('UTC')
    end

    context 'with the flag on' do
      before { account.enable_features!(described_class::FEATURE) }

      it 'returns the account timezone and leaves the column untouched' do
        expect(inbox.reload.timezone).to eq('America/Sao_Paulo')
        expect(inbox[:timezone]).to eq('UTC')
      end

      it 'turns a Rails zone name of the account into the IANA name the inbox validates' do
        account.update!(reporting_timezone: 'Brasilia')

        expect(inbox.reload.timezone).to eq('America/Sao_Paulo')
        expect(inbox).to be_valid
      end

      it 'falls back to the column when the account has no valid timezone' do
        account.update_column(:settings, account.settings.except('reporting_timezone')) # rubocop:disable Rails/SkipsModelValidations

        expect(inbox.reload.timezone).to eq('UTC')
      end

      it 'reads the working hours in the account timezone' do
        inbox.update!(working_hours_enabled: true) # padrão: seg-sex 9h-17h

        # Quarta, 15:00 em São Paulo = 18:00 UTC (fora das 9h-17h se fosse UTC).
        travel_to(Time.zone.parse('2026-09-02 15:00 -03:00')) { expect(inbox.reload).not_to be_out_of_office }
      end

      it 'still saves the account timezone in the column of a new inbox, so turning the flag off keeps it' do
        expect(create(:inbox, account: account)[:timezone]).to eq('America/Sao_Paulo')
      end
    end
  end
end
