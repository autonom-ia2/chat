require 'rails_helper'
require Rails.root.join('db/migrate/20261004220000_ligar_aviso_do_guia_para_administradores.rb')

# #944 — o aviso urgente do Guia ligado no e-mail e no push dos administradores que já existiam. Só o bit
# do `guide_alert`, só administrador, só quem não mexeu nas preferências depois que a opção apareceu, e
# rodar duas vezes dá o mesmo resultado.
RSpec.describe LigarAvisoDoGuiaParaAdministradores do
  let(:account) { create(:account) }
  let(:antes_da_opcao) { Time.utc(2026, 10, 1, 12) }
  let(:depois_da_opcao) { Time.utc(2026, 10, 4, 6) }
  # Só a atribuição de conversa ligada no e-mail; no push, só a menção: o resto a pessoa desligou.
  let(:email_antigo) { 1 << (Notification::NOTIFICATION_TYPES[:conversation_assignment] - 1) }
  let(:push_antigo) { 1 << (Notification::NOTIFICATION_TYPES[:conversation_mention] - 1) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  # A preferência como estava antes do #935: sem o bit do aviso do Guia.
  def preferencia_antiga(role, atualizada_em: antes_da_opcao)
    user = create(:user, account: account, role: role)
    setting = user.notification_settings.find_by(account: account)
    setting.update_columns(email_flags: email_antigo, push_flags: push_antigo, updated_at: atualizada_em) # rubocop:disable Rails/SkipsModelValidations
    setting
  end

  it 'liga e-mail e push do aviso do Guia no administrador, sem mexer nos outros tipos', :aggregate_failures do
    setting = preferencia_antiga(:administrator)

    described_class.new.up

    setting.reload
    expect([setting.email_guide_alert?, setting.push_guide_alert?]).to eq([true, true])
    expect(setting.email_flags).to eq(email_antigo | described_class::GUIDE_ALERT_BIT)
    expect(setting.push_flags).to eq(push_antigo | described_class::GUIDE_ALERT_BIT)
    expect([setting.email_conversation_mention?, setting.push_conversation_assignment?]).to eq([false, false])
  end

  it 'não toca agente comum' do
    setting = preferencia_antiga(:agent)

    expect { described_class.new.up }.not_to(change { setting.reload.attributes })
  end

  it 'não toca quem salvou as preferências depois que a opção apareceu' do
    setting = preferencia_antiga(:administrator, atualizada_em: depois_da_opcao)

    expect { described_class.new.up }.not_to(change { setting.reload.attributes })
  end

  it 'rodar de novo não muda nada', :aggregate_failures do
    setting = preferencia_antiga(:administrator)
    described_class.new.up
    depois_da_primeira = setting.reload.attributes

    described_class.new.up

    expect(setting.reload.attributes).to eq(depois_da_primeira)
    expect(setting.updated_at).to eq(antes_da_opcao)
  end

  it 'cobre preferências em lotes diferentes' do
    stub_const("#{described_class}::LOTE", 1)
    settings = Array.new(3) { preferencia_antiga(:administrator) }

    described_class.new.up

    expect(settings.map { |setting| setting.reload.email_guide_alert? }).to eq([true, true, true])
  end
end
