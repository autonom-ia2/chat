require 'rails_helper'

# #1426 (tema 4, decisão do Rodrigo) — a foto mandada na criação, além de ir para a conversa com o Construtor, entra na
# base como material: é lida (OCR) e revisada como qualquer arquivo. Só com a Fase 2 ligada e só na criação (rascunho).
RSpec.describe Autonomia::Agents::Knowledge::FotosDaCriacao do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'custom', status: :draft)
  end
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account, agent: agent) }
  let(:png) { Rails.root.join('spec/fixtures/files/autonomia/foto_da_criacao/cardapio-legivel.png').binread }

  before { Autonomia::Agents::Fase2.ligar!(account) }

  def foto(nome = 'tabela.png', conta: account, bytes: png)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(bytes), filename: nome, content_type: 'image/png', identify: false,
      metadata: { autonomia_account_id: conta.id }
    )
    blob.signed_id(purpose: :autonomia_builder_image, expires_in: 1.day)
  end

  def fotos_na_base
    agent.sources.where(source_type: 'foto')
  end

  def mandar(*ids)
    thread.append_message!('user', 'Segue a foto da tabela', image_signed_ids: ids)
  end

  it 'turns the photo of the last turn into a knowledge source that is read and reviewed' do
    # Arrange
    mandar(foto)

    # Act / Assert
    expect { described_class.new(thread).para_base! }
      .to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)

    source = fotos_na_base.sole
    expect(source).to be_kind_knowledge
    expect(source.reference).to eq('tabela.png')
    expect(source.file).to be_attached
    expect(source.metadata['mime']).to eq('image/png')
    expect(source.origem).to eq(Autonomia::Agents::Source::ORIGEM_FOTO_DA_CRIACAO)
  end

  it 'reuses the uploaded photo instead of storing a second copy' do
    # Arrange
    id = foto
    mandar(id)

    # Act
    described_class.new(thread).para_base!

    # Assert
    expect(fotos_na_base.sole.file.blob).to eq(ActiveStorage::Blob.find_signed(id, purpose: :autonomia_builder_image))
  end

  it 'does not add the same photo twice when the turn is built again' do
    # Arrange
    mandar(foto)
    described_class.new(thread).para_base!

    # Act
    described_class.new(thread).para_base!

    # Assert
    expect(fotos_na_base.count).to eq(1)
  end

  it 'only takes the photos of the last turn (earlier turns were handled when they were built)' do
    # Arrange
    mandar(foto('antiga.png'))
    thread.append_message!('assistant', 'Entendi.')
    mandar(foto('nova.png'))

    # Act
    described_class.new(thread).para_base!

    # Assert
    expect(fotos_na_base.pluck(:reference)).to eq(['nova.png'])
  end

  # A2 — a mesma conferência da porta: tipo pelos bytes e teto de pixels (bomba de pixels).
  it 'ignores what is not a real photo, or a pixel bomb' do
    bomba = ["\x89PNG\r\n\x1a\n", [13].pack('N'), 'IHDR', [14_000, 14_000].pack('NN'), "\x00" * 64].map(&:b).join
    mandar(foto('texto.png', bytes: "/etc/passwd\n"), foto('bomba.png', bytes: bomba))

    described_class.new(thread).para_base!

    expect(fotos_na_base).to be_empty
  end

  # A7 — a checagem e a gravação correm sob a trava da linha do agente.
  it 'checks and writes under the lock of the agent' do
    mandar(foto)
    allow(agent).to receive(:with_lock).and_call_original
    allow(thread).to receive(:agent).and_return(agent)

    described_class.new(thread).para_base!

    expect(agent).to have_received(:with_lock)
    expect(fotos_na_base.count).to eq(1)
  end

  it 'ignores a photo uploaded by another account' do
    # Arrange
    mandar(foto(conta: create(:account)))

    # Act
    described_class.new(thread).para_base!

    # Assert
    expect(fotos_na_base).to be_empty
  end

  it 'does not go over the knowledge limit of the agent' do
    # Arrange
    Autonomia::Agents::Source::MAX_KNOWLEDGE_SOURCES.times do |i|
      agent.sources.create!(account: account, source_type: 'txt', reference: "doc-#{i}.txt")
    end
    mandar(foto)
    allow(Rails.logger).to receive(:info)

    # Act
    described_class.new(thread).para_base!

    # Assert
    expect(fotos_na_base).to be_empty
    limite = Autonomia::Agents::Source::MAX_KNOWLEDGE_SOURCES
    expect(Rails.logger).to have_received(:info)
      .with("[autonomia][fotos_da_criacao] base_cheia agent=#{agent.id} materiais=#{limite}")
  end

  it 'does nothing without the Fase 2' do
    # Arrange
    Autonomia::Agents::Fase2.desligar!(account)
    mandar(foto)

    # Act
    described_class.new(thread).para_base!

    # Assert
    expect(fotos_na_base).to be_empty
  end

  it 'does nothing when adjusting an agent that is already working (only the creation)' do
    # Arrange
    agent.update!(status: :active)
    mandar(foto)

    # Act
    described_class.new(thread).para_base!

    # Assert
    expect(fotos_na_base).to be_empty
  end

  it 'does nothing while the conversation has no agent yet' do
    # Arrange
    thread.update!(agent: nil)
    mandar(foto)

    # Act / Assert
    expect { described_class.new(thread).para_base! }.not_to(change(Autonomia::Agents::Source, :count))
  end

  it 'leaves the quote agent (Lia) untouched' do
    # Arrange
    lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :draft)
    thread.update!(agent: lia)
    mandar(foto)

    # Act
    described_class.new(thread).para_base!

    # Assert
    expect(lia.sources).to be_empty
  end
end
