require 'rails_helper'

# #1337: aviso da Meta sobre um modelo (situação, qualidade, tipo) muda a lista da caixa na hora, sem esperar o sync.
RSpec.describe Whatsapp::Templates::WebhookEvent do
  let(:waba_id) { '1029384756' }
  let(:account) { create(:account) }
  let(:event_time) { 1_791_000_000 }
  let(:aviso) do
    { 'id' => '594425479261596', 'name' => 'aviso', 'language' => 'pt_BR', 'status' => 'PENDING', 'category' => 'UTILITY',
      'quality_score' => { 'score' => 'UNKNOWN', 'date' => 1_790_000_000 } }
  end
  let(:promo) { { 'id' => '77', 'name' => 'promo', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING' } }
  let!(:channel) { cloud_channel(waba_id, [aviso, promo]) }

  # A factory troca o business_account_id da caixa Cloud: a WABA é gravada depois.
  def cloud_channel(waba, templates, provider: 'whatsapp_cloud')
    created = create(:channel_whatsapp, account: account, provider: provider, sync_templates: false, validate_provider_config: false)
    created.update_columns( # rubocop:disable Rails/SkipsModelValidations
      provider_config: created.provider_config.merge('business_account_id' => waba),
      message_templates: templates, message_templates_last_updated: Time.zone.at(event_time - 600)
    )
    created
  end

  def status_event(event, time: event_time, template_id: aviso['id'], **extra)
    described_class.new(
      waba_id: waba_id, field: 'message_template_status_update', time: time,
      value: { 'event' => event, 'message_template_id' => template_id.to_i, 'message_template_name' => 'aviso',
               'message_template_language' => 'pt-BR', 'reason' => 'NONE' }.merge(extra)
    )
  end

  def entry(target = channel, id = aviso['id'])
    target.reload.message_templates.find { |item| item['id'] == id }
  end

  before { allow(Channels::Whatsapp::TemplatesSyncJob).to receive(:perform_later) }

  describe 'situação (message_template_status_update)' do
    it 'APPROVED: o modelo fica pronto e os outros não mudam' do
      status_event('APPROVED').perform

      expect(entry['status']).to eq('APPROVED')
      expect(entry(channel, '77')).to eq(promo)
      expect(Channels::Whatsapp::TemplatesSyncJob).not_to have_received(:perform_later)
    end

    it 'REJECTED: grava o motivo da Meta' do
      status_event('REJECTED', 'reason' => 'INVALID_FORMAT').perform

      expect(entry).to include('status' => 'REJECTED', 'rejected_reason' => 'INVALID_FORMAT')
    end

    it 'REINSTATED: volta a pronto' do
      channel.update_columns(message_templates: [aviso.merge('status' => 'PAUSED'), promo]) # rubocop:disable Rails/SkipsModelValidations

      status_event('REINSTATED').perform

      expect(entry['status']).to eq('APPROVED')
    end

    it 'evento sem situação equivalente na lista (FLAGGED, LOCKED, UNARCHIVED): não chuta, pede o sync da caixa' do
      %w[FLAGGED LOCKED UNARCHIVED].each { |event| status_event(event).perform }

      expect(entry['status']).to eq('PENDING')
      expect(Channels::Whatsapp::TemplatesSyncJob).to have_received(:perform_later).with(channel).exactly(3).times
    end

    it 'acha o modelo pelo id da Meta mesmo com o idioma escrito de outro jeito (pt-BR × pt_BR)' do
      status_event('PAUSED').perform

      expect(entry['status']).to eq('PAUSED')
    end
  end

  describe 'fora de ordem e repetido' do
    it 'evento mais antigo que o último aplicado não regride a situação' do
      status_event('APPROVED', time: event_time + 10).perform
      status_event('PENDING', time: event_time).perform

      expect(entry['status']).to eq('APPROVED')
    end

    it 'evento repetido não muda nada' do
      status_event('APPROVED').perform
      before_repeat = channel.reload.message_templates

      status_event('APPROVED').perform

      expect(channel.reload.message_templates).to eq(before_repeat)
      expect(Channels::Whatsapp::TemplatesSyncJob).not_to have_received(:perform_later)
    end

    it 'dois eventos diferentes no mesmo segundo: a ordem é incerta, então pede o sync' do
      status_event('APPROVED').perform
      status_event('PAUSED').perform

      expect(Channels::Whatsapp::TemplatesSyncJob).to have_received(:perform_later).with(channel)
    end

    it 'evento anterior ao último sync da caixa: não muda a lista e pede outro sync (o carimbo pode ser de busca que falhou)' do
      channel.update_columns(message_templates_last_updated: Time.zone.at(event_time + 60)) # rubocop:disable Rails/SkipsModelValidations

      status_event('APPROVED').perform

      expect(entry['status']).to eq('PENDING')
      expect(Channels::Whatsapp::TemplatesSyncJob).to have_received(:perform_later).with(channel)
    end

    it 'cada tipo de aviso tem a própria ordem: qualidade antiga não barra situação nova' do
      described_class.new(waba_id: waba_id, field: 'message_template_quality_update', time: event_time + 30,
                          value: { 'message_template_id' => aviso['id'].to_i, 'new_quality_score' => 'GREEN' }).perform
      status_event('APPROVED').perform

      expect(entry).to include('status' => 'APPROVED')
      expect(entry['quality_score']['score']).to eq('GREEN')
    end
  end

  describe 'qualidade (message_template_quality_update)' do
    it 'troca a nota e mantém a data que veio do sync' do
      described_class.new(waba_id: waba_id, field: 'message_template_quality_update', time: event_time,
                          value: { 'previous_quality_score' => 'UNKNOWN', 'new_quality_score' => 'RED',
                                   'message_template_id' => aviso['id'].to_i }).perform

      expect(entry['quality_score']).to eq('score' => 'RED', 'date' => 1_790_000_000)
    end
  end

  describe 'tipo (template_category_update)' do
    it 'mudança feita: grava o tipo novo e o anterior' do
      described_class.new(waba_id: waba_id, field: 'template_category_update', time: event_time,
                          value: { 'message_template_id' => aviso['id'].to_i, 'previous_category' => 'UTILITY',
                                   'new_category' => 'MARKETING' }).perform

      expect(entry).to include('category' => 'MARKETING', 'previous_category' => 'UTILITY')
    end

    it 'aviso de mudança em 24 h: guarda o tipo previsto e não troca o tipo atual' do
      described_class.new(waba_id: waba_id, field: 'template_category_update', time: event_time,
                          value: { 'message_template_id' => aviso['id'].to_i, 'new_category' => 'UTILITY',
                                   'correct_category' => 'MARKETING', 'category_update_timestamp' => event_time + 86_400 }).perform

      expect(entry).to include('category' => 'UTILITY', 'correct_category' => 'MARKETING')
    end
  end

  describe 'caixas da WABA' do
    it 'várias caixas na mesma WABA (inclusive de outra conta): atualiza todas' do
      other = cloud_channel(waba_id, [aviso])
      other.update_columns(account_id: create(:account).id) # rubocop:disable Rails/SkipsModelValidations

      status_event('APPROVED').perform

      expect([entry['status'], entry(other)['status']]).to eq(%w[APPROVED APPROVED])
    end

    it 'caixa de outra WABA ou de outro provedor não muda' do
      foreign = cloud_channel('555', [aviso])
      dialog = cloud_channel(waba_id, [aviso], provider: 'default')

      status_event('APPROVED').perform

      expect([entry(foreign)['status'], entry(dialog)['status']]).to eq(%w[PENDING PENDING])
    end

    it 'modelo que a caixa ainda não tem (criado no WhatsApp Manager): pede o sync, sem inventar a entrada' do
      status_event('APPROVED', template_id: '999').perform

      expect(channel.reload.message_templates).to eq([aviso, promo])
      expect(Channels::Whatsapp::TemplatesSyncJob).to have_received(:perform_later).with(channel)
    end

    it 'WABA sem caixa: só registra, sem erro' do
      event = described_class.new(waba_id: 'nenhuma', field: 'message_template_status_update', time: event_time,
                                  value: { 'event' => 'APPROVED', 'message_template_id' => 1 })

      expect { event.perform }.not_to raise_error
    end
  end

  it 'log só com ids e situação: nada do nome do modelo nem do texto da Meta' do
    allow(Rails.logger).to receive(:info)

    status_event('REJECTED', 'reason' => 'INVALID_FORMAT', 'rejection_info' => { 'reason' => 'texto da meta' }).perform

    expect(Rails.logger).to have_received(:info).with(a_string_including("waba_id=#{waba_id}", 'result=changed'))
    expect(Rails.logger).not_to have_received(:info).with(a_string_including('aviso'))
    expect(Rails.logger).not_to have_received(:info).with(a_string_including('texto da meta'))
  end
end
