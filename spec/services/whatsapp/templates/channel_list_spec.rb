require 'rails_helper'

# #1382: todos os escritores da lista da caixa gravam com trava e trocam só a entrada do modelo.
RSpec.describe Whatsapp::Templates::ChannelList do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false, message_templates: [])
  end
  let(:aviso) { { 'id' => '1', 'name' => 'aviso', 'language' => 'pt_BR', 'status' => 'PAUSED', 'quality_score' => { 'score' => 'RED' } } }
  let(:promo) { { 'id' => '2', 'name' => 'promo', 'language' => 'pt_BR', 'status' => 'APPROVED' } }

  before { channel.update_columns(message_templates: [aviso, promo]) } # rubocop:disable Rails/SkipsModelValidations

  describe '.upsert!' do
    it 'merge: troca a entrada pelo id, mantém os campos que o item não traz e não mexe nas outras' do
      described_class.upsert!(channel, { 'id' => '1', 'name' => 'aviso', 'language' => 'pt_BR', 'status' => 'APPROVED' }, merge: true)

      expect(channel.reload.message_templates).to eq([aviso.merge('status' => 'APPROVED'), promo])
    end

    it 'merge sem id: acha pelo nome e idioma (sem diferença de maiúscula no idioma)' do
      described_class.upsert!(channel, { 'name' => 'promo', 'language' => 'PT_br', 'status' => 'PAUSED' }, merge: true)

      expect(channel.reload.message_templates.last).to include('id' => '2', 'status' => 'PAUSED')
      expect(channel.message_templates.size).to eq(2)
    end

    it 'sem merge: troca a entrada inteira (item completo, campos velhos como o motivo de recusa somem)' do
      channel.update_columns(message_templates: [aviso.merge('rejected_reason' => 'INVALID_FORMAT'), promo]) # rubocop:disable Rails/SkipsModelValidations
      approved = { 'id' => '1', 'name' => 'aviso', 'language' => 'pt_BR', 'status' => 'APPROVED' }

      described_class.upsert!(channel, approved)

      expect(channel.reload.message_templates).to eq([approved, promo])
    end

    it 'modelo apagado e criado de novo na Meta (outro id, mesmo nome e idioma) troca a entrada, sem duplicar' do
      recreated = { 'id' => '99', 'name' => 'aviso', 'language' => 'pt_BR', 'status' => 'PENDING' }

      described_class.upsert!(channel, recreated)

      expect(channel.reload.message_templates).to eq([recreated, promo])
    end

    # #1383 (CI do agendamento): o stub da Graph devolvia o mesmo id para dois avisos criados em sequência e o segundo
    # apagava o primeiro. Nome + idioma é a chave única da Meta; id repetido com outro nome não sobrescreve.
    it 'mesmo id com outro nome: entra como outro modelo, não apaga o primeiro, e avisa no log' do
      allow(Rails.logger).to receive(:warn)
      booked = { 'id' => '1', 'name' => 'aviso_marcado', 'language' => 'pt_BR', 'status' => 'PENDING' }
      hour_before = { 'id' => '1', 'name' => 'aviso_uma_hora', 'language' => 'pt_BR', 'status' => 'PENDING' }
      channel.update_columns(message_templates: []) # rubocop:disable Rails/SkipsModelValidations

      described_class.upsert!(channel, booked)
      described_class.upsert!(channel, hour_before)

      expect(channel.reload.message_templates).to eq([booked, hour_before])
      expect(Rails.logger).to have_received(:warn).with(a_string_including('channel_list_id_clash'))
    end

    it 'sem id dos dois lados e nomes diferentes: são modelos diferentes (nil não casa com nil)' do
      booked = { 'name' => 'aviso_marcado', 'language' => 'pt_BR', 'status' => 'PENDING' }
      hour_before = { 'name' => 'aviso_uma_hora', 'language' => 'pt_BR', 'status' => 'PENDING' }
      channel.update_columns(message_templates: [booked]) # rubocop:disable Rails/SkipsModelValidations

      described_class.upsert!(channel, hour_before)

      expect(channel.reload.message_templates).to eq([booked, hour_before])
    end

    it 'only_existing: não acrescenta modelo que não está na lista' do
      described_class.upsert!(channel, { 'name' => 'novo', 'language' => 'en' }, merge: true, only_existing: true)

      expect(channel.reload.message_templates).to eq([aviso, promo])
    end

    it 'modelo que não está na lista entra no fim' do
      novo = { 'id' => '3', 'name' => 'novo', 'language' => 'en', 'status' => 'PENDING' }

      described_class.upsert!(channel, novo)

      expect(channel.reload.message_templates).to eq([aviso, promo, novo])
    end

    it 'relê a lista sob a trava: não apaga o que outro escritor gravou depois que o objeto foi carregado' do
      stale = Channel::Whatsapp.find(channel.id)
      described_class.upsert!(channel, { 'id' => '3', 'name' => 'novo', 'language' => 'en' })

      described_class.upsert!(stale, { 'id' => '1', 'status' => 'APPROVED' }, merge: true)

      expect(channel.reload.message_templates.pluck('id')).to eq(%w[1 2 3])
      expect(stale.message_templates.size).to eq(3)
    end

    it 'aceita a lista guardada como objeto vazio ({}, padrão da coluna)' do
      channel.update_columns(message_templates: {}) # rubocop:disable Rails/SkipsModelValidations

      described_class.upsert!(channel, promo)

      expect(channel.reload.message_templates).to eq([promo])
    end
  end

  it '.remove! tira só o modelo pedido' do
    described_class.remove!(channel, { 'name' => 'aviso', 'language' => 'pt_BR' })

    expect(channel.reload.message_templates).to eq([promo])
  end

  describe '.replace!' do
    let(:base) { [aviso, promo] }
    let(:from_meta) { [aviso.merge('status' => 'APPROVED')] }

    it 'sem escrita concorrente, vale a lista da Meta e o carimbo do sync' do
      described_class.replace!(channel, from_meta, base: base)

      expect(channel.reload.message_templates).to eq(from_meta)
      expect(channel.message_templates_last_updated).to be_within(5.seconds).of(Time.current)
    end

    it 'lista zerada durante a busca (troca de conta do WhatsApp): não grava nem carimba' do
      channel.update_columns(message_templates: [], message_templates_last_updated: nil) # rubocop:disable Rails/SkipsModelValidations

      described_class.replace!(channel, from_meta, base: base)

      expect(channel.reload.message_templates).to eq([])
      expect(channel.message_templates_last_updated).to be_nil
    end

    it 'mantém o que outro escritor criou, mudou ou apagou enquanto o sync buscava' do
      created = { 'id' => '3', 'name' => 'novo', 'language' => 'en', 'status' => 'PENDING' }
      edited = promo.merge('status' => 'PENDING')
      channel.update_columns(message_templates: [edited, created]) # rubocop:disable Rails/SkipsModelValidations
      from_meta = [aviso.merge('status' => 'APPROVED'), promo]

      described_class.replace!(channel, from_meta, base: base)

      # aviso foi apagado pela tela no meio do sync; promo foi editado; novo foi criado
      expect(channel.reload.message_templates).to eq([edited, created])
    end
  end
end
