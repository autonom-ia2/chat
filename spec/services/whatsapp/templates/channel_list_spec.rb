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
    it 'troca a entrada pelo id, mantém os campos que o item não traz e não mexe nas outras' do
      described_class.upsert!(channel, { 'id' => '1', 'name' => 'aviso', 'language' => 'pt_BR', 'status' => 'APPROVED' })

      expect(channel.reload.message_templates).to eq([aviso.merge('status' => 'APPROVED'), promo])
    end

    it 'sem id, acha pelo nome e idioma (sem diferença de maiúscula no idioma)' do
      described_class.upsert!(channel, { 'name' => 'promo', 'language' => 'PT_br', 'status' => 'PAUSED' })

      expect(channel.reload.message_templates.last).to include('id' => '2', 'status' => 'PAUSED')
      expect(channel.message_templates.size).to eq(2)
    end

    it 'modelo que não está na lista entra no fim' do
      novo = { 'id' => '3', 'name' => 'novo', 'language' => 'en', 'status' => 'PENDING' }

      described_class.upsert!(channel, novo)

      expect(channel.reload.message_templates).to eq([aviso, promo, novo])
    end

    it 'relê a lista sob a trava: não apaga o que outro escritor gravou depois que o objeto foi carregado' do
      stale = Channel::Whatsapp.find(channel.id)
      described_class.upsert!(channel, { 'id' => '3', 'name' => 'novo', 'language' => 'en' })

      described_class.upsert!(stale, { 'id' => '1', 'status' => 'APPROVED' })

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
