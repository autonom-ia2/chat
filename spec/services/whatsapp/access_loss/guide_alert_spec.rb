require 'rails_helper'

# #2907: perda de acesso CONFIRMADA (checagem de saúde ou aviso account_update da Meta) faz o Guia avisar os administradores
# pelo canal urgente (conversa do Guia + notificação guide_alert: sino, push e e-mail). Uma vez por queda.
RSpec.describe Whatsapp::AccessLoss::GuideAlert do
  let(:conta) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, account: conta, role: :administrator) }
  let!(:agente) { create(:user, account: conta, role: :agent) }
  let!(:channel) do
    create(:channel_whatsapp, account: conta, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).tap do |record|
      record.update_columns(provider_config: record.provider_config.merge('business_account_id' => 'waba-2907')) # rubocop:disable Rails/SkipsModelValidations
    end
  end
  let(:avisos) { Autonomia::Guide::Aviso.where(account: conta) }

  after { channel.reauthorized! }

  def perdeu_pela_meta
    Whatsapp::AccessLoss::AccountUpdateJob.perform_now([{ 'entry_id' => 'waba-2907', 'value' => { 'event' => 'PARTNER_REMOVED' } }])
  end

  it 'aviso da Meta: o admin recebe o aviso urgente com o nome da caixa e a notificação; o agente, nada' do
    perdeu_pela_meta

    aviso = avisos.find_by(user: admin)
    expect(aviso.gravidade).to eq(Autonomia::Guide::Aviso::URGENTE)
    expect(aviso.texto).to include(channel.inbox.name, 'perdeu a conexão')
    expect(aviso.sinal).to eq('inbox_id' => channel.inbox.id)
    expect(Notification.where(user: admin, notification_type: :guide_alert).count).to eq(1)
    expect(avisos.where(user: agente)).to be_empty
  end

  it 'checagem de saúde: avisa quando o segundo erro de autorização marca a caixa, não no primeiro' do
    error = Whatsapp::HealthService::ApiError.new(message: 'x', http_status: 400, code: 100, subcode: 33)
    service = Whatsapp::HealthService.new(channel)

    service.send(:record_access_error, error)
    expect(avisos).to be_empty

    service.send(:record_access_error, error)
    expect(avisos.where(user: admin).count).to eq(1)
  end

  it 'a mesma queda avisa uma vez só, mesmo com vários sinais no mesmo segundo (Meta + checagem)' do
    perdeu_pela_meta
    perdeu_pela_meta
    described_class.avisar!(channel)

    expect(avisos.where(user: admin).count).to eq(1)
  end

  it 'depois de reconectar, a próxima queda avisa de novo' do
    perdeu_pela_meta
    channel.reauthorized!
    travel 1.second do
      perdeu_pela_meta
    end

    expect(avisos.where(user: admin).count).to eq(2)
  end

  it 'marcação que não confirma perda (webhook falho, número pendente no cadastro) não avisa' do
    channel.prompt_reauthorization!

    expect(channel.reauthorization_required?).to be(true)
    expect(avisos).to be_empty
  end

  it 'WhatsApp que não é a API oficial não avisa por aqui' do
    channel.update_columns(provider: 'default') # rubocop:disable Rails/SkipsModelValidations

    described_class.avisar!(channel)

    expect(avisos).to be_empty
  end

  it 'entrega que falhou não trava a queda: o próximo sinal avisa' do
    allow(Autonomia::Guide::Entrega).to receive(:new).and_raise(StandardError, 'fora')
    perdeu_pela_meta
    allow(Autonomia::Guide::Entrega).to receive(:new).and_call_original

    perdeu_pela_meta

    expect(avisos.where(user: admin).count).to eq(1)
  end

  it 'entrega que falhou no aviso da Meta sai na próxima checagem de saúde, mesmo com a Graph respondendo bem' do
    allow(Autonomia::Guide::Entrega).to receive(:new).and_raise(StandardError, 'fora')
    perdeu_pela_meta
    expect(avisos).to be_empty
    allow(Autonomia::Guide::Entrega).to receive(:new).and_call_original

    Whatsapp::HealthService.new(channel).send(:record_access_ok)

    expect(avisos.where(user: admin).count).to eq(1)
    expect(channel.reauthorization_required?).to be(true)
  end

  it 'marcada pela Meta, a checagem de saúde boa não apaga, mesmo com erro de autorização contado antes' do
    perdeu_pela_meta
    channel.authorization_error!

    Whatsapp::HealthService.new(channel).send(:record_access_ok)

    expect(channel.reauthorization_required?).to be(true)
  end

  it 'falha no aviso não impede a marcação' do
    allow(Autonomia::Guide::Entrega).to receive(:new).and_raise(StandardError, 'fora')

    perdeu_pela_meta

    expect(channel.reauthorization_required?).to be(true)
  end
end
