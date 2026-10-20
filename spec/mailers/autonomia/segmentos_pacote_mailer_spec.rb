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

  it 'leva a data do lembrete na fala da corretora (#1802)' do
    stub_const('PacoteLembreteMailer', Class.new(ApplicationMailer) do
      def aviso
        mail(to: 'pessoa@example.com', subject: I18n.t('crm.follow_up_reminder.due_at', time: '20/10 10:00'), body: 'x')
      end
    end)

    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      expect(PacoteLembreteMailer.with(account: conta('seguros', 'corretora')).aviso.subject).to eq('Marcado para: 20/10 10:00')
      expect(PacoteLembreteMailer.with(account: conta('geral')).aviso.subject).to eq('Vence em: 20/10 10:00')
    end
  end

  describe 'lembrete do CRM por e-mail (#1802, lote 5)' do
    def corpo_do_lembrete(account)
      agent = create(:user, account: account)
      follow_up = account.crm_follow_ups.create!(title: 'Conferir as renovações da semana', due_at: 1.day.from_now,
                                                 timezone: 'UTC', created_by: agent)
      email = Crm::FollowUpReminderMailer.with(account: account).reminder(follow_up, agent)
      email.body.decoded
    end

    around { |example| with_modified_env(SMTP_ADDRESS: 'smtp.example.com') { example.run } }

    it 'diz quando o lembrete foi marcado, sem confundir com o vencimento do seguro' do
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
        corretora = corpo_do_lembrete(conta('seguros', 'corretora'))
        expect(corretora).to include('Marcado para:')
        expect(corretora).not_to include('Vence em:')
        expect(corpo_do_lembrete(conta('geral'))).to include('Vence em:')
      end
    end

    it 'diz "Vence em" na corretora com o interruptor desligado' do
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) do
        expect(corpo_do_lembrete(conta('seguros', 'corretora'))).to include('Vence em:')
      end
    end
  end

  it 'escreve com o geral com o interruptor desligado' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) do
      expect(PacoteTesteMailer.with(account: conta('seguros', 'saude_beneficios')).aviso.subject).to eq('Ganho')
    end
  end
end
