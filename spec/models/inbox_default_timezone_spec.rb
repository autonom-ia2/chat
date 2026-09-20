require 'rails_helper'

RSpec.describe Inbox do
  let(:account) { create(:account) }

  describe 'fuso padrão da caixa nova' do
    it 'mantém UTC quando a conta não definiu fuso' do
      inbox = create(:inbox, account: account)

      expect(inbox.timezone).to eq('UTC')
    end

    it 'prefere o fuso de relatórios da conta' do
      account.update!(reporting_timezone: 'America/Manaus')

      inbox = create(:inbox, account: account)

      expect(inbox.timezone).to eq('America/Manaus')
    end

    it 'UTC na criação vira o fuso da conta: o padrão da coluna não distingue escolha' do
      account.update!(reporting_timezone: 'America/Manaus')

      inbox = create(:inbox, account: account, timezone: 'UTC')

      expect(inbox.timezone).to eq('America/Manaus')
      expect(inbox.reload.update!(timezone: 'UTC')).to be true
    end

    it 'respeita o fuso escolhido na criação' do
      inbox = create(:inbox, account: account, timezone: 'Europe/Lisbon')

      expect(inbox.timezone).to eq('Europe/Lisbon')
    end

    it 'não mexe no fuso de caixa já existente' do
      inbox = create(:inbox, account: account)
      inbox.update!(timezone: 'UTC')

      inbox.update!(name: 'Comercial')

      expect(inbox.reload.timezone).to eq('UTC')
    end

    it 'conta criada pelo cadastro nasce no fuso da operação e passa para a caixa' do
      allow(Account::SignUpEmailValidationService).to receive(:new).and_return(
        instance_double(Account::SignUpEmailValidationService, perform: true)
      )

      with_modified_env CRM_DEFAULT_TIMEZONE: 'America/Bahia' do
        _usuario, nova_conta = AccountBuilder.new(
          account_name: 'Corretora',
          email: 'dona@corretora.com.br',
          user_full_name: 'Dona da Corretora',
          user_password: 'Password123!',
          confirmed: true
        ).perform

        expect(nova_conta.reporting_timezone).to eq('America/Bahia')
        expect(create(:inbox, account: nova_conta).timezone).to eq('America/Bahia')
      end
    end
  end
end
