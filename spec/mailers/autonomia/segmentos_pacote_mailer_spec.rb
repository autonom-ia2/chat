# frozen_string_literal: true

require 'rails_helper'

# #1550 — e-mail sai com o pacote de tradução da conta (ApplicationMailer.with(account:)).
RSpec.describe 'Pacote de tradução da conta no e-mail', type: :mailer do
  let(:nicho) { Autonomia::Agents::Nicho }

  before do
    stub_const('PacoteTesteMailer', Class.new(ApplicationMailer) do
      def aviso
        mail(to: 'pessoa@example.com', subject: I18n.t('crm.export.statuses.won'), body: 'x')
      end
    end)
  end

  after { ActiveSupport::IsolatedExecutionState.delete(AutonomiaPacotesI18nLookup::ESTADO) }

  def conta(nicho_escolhido, perfil = nil)
    create(:account, locale: 'pt_BR',
                     internal_attributes: { nicho::NICHO_KEY => nicho_escolhido, nicho::PERFIL_KEY => perfil }.compact)
  end

  it 'escreve com o pacote da conta e não deixa a camada para depois' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      expect(PacoteTesteMailer.with(account: conta('seguros', 'corretora')).aviso.subject).to eq('Seguro ativo')
      expect(Autonomia::Segmentos::Pacotes.ativas).to eq([])

      expect(PacoteTesteMailer.with(account: conta('geral')).aviso.subject).to eq('Ganho')
    end
  end

  it 'leva o card do lembrete na fala da corretora (#1802)' do
    stub_const('PacoteLembreteMailer', Class.new(ApplicationMailer) do
      def aviso
        mail(to: 'pessoa@example.com', subject: I18n.t('crm.follow_up_reminder.card', card: 'Seguro do carro'), body: 'x')
      end
    end)

    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      expect(PacoteLembreteMailer.with(account: conta('seguros', 'corretora')).aviso.subject).to eq('Card: Seguro do carro')
      expect(PacoteLembreteMailer.with(account: conta('geral')).aviso.subject).to eq('Negócio: Seguro do carro')
    end
  end

  it 'escreve com o geral com o interruptor desligado' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) do
      expect(PacoteTesteMailer.with(account: conta('seguros', 'saude_beneficios')).aviso.subject).to eq('Ganho')
    end
  end
end
