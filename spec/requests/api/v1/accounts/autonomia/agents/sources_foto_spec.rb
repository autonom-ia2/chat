require 'rails_helper'

# #1426 — o tipo `foto` (a foto da criação como material) pela API: só na Fase 2, só no que o agente sabe, nunca na Lia, e
# só imagem de verdade, conferida pelos BYTES (um texto declarado como image/png nunca chega ao tesseract). O arquivo vem
# só como upload: texto em `file` (signed_id de um blob que já existe) é recusado.
RSpec.describe 'Autonomia sources - foto', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support', mode: :guided,
                                     status: :draft, enabled: false, actuation: :external)
  end
  let(:png) { Rails.root.join('spec/fixtures/files/autonomia/foto_da_criacao/cardapio-legivel.png').binread }
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources" }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def arquivo(bytes, tipo: 'image/png', nome: 'tabela.png')
    Rack::Test::UploadedFile.new(StringIO.new(bytes), tipo, original_filename: nome)
  end

  def png_declarando(largura, altura)
    ["\x89PNG\r\n\x1a\n", [13].pack('N'), 'IHDR', [largura, altura].pack('NN'), "\x08\x02\x00\x00\x00", "\x00" * 64].map(&:b).join
  end

  def enviar(file:, source_type: 'foto', kind: nil)
    source = { source_type: source_type, reference: 'tabela.png', kind: kind }.compact
    post url, params: { source: source, file: file }, headers: administrator.create_new_auth_token
  end

  def expect_recusa(chave)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t("autonomia.source.#{chave}"))
    expect(agent.sources.count).to eq(0)
  end

  it 'refuses a foto outside the Fase 2 with a clear message and creates nothing' do
    enviar(file: arquivo(png))

    expect_recusa('foto_fora_da_fase2')
  end

  context 'with the Fase 2' do
    before { Autonomia::Agents::Fase2.ligar!(account) }

    it 'accepts a real photo and sends it to be read and reviewed' do
      expect { enviar(file: arquivo(png)) }.to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)

      expect(response).to have_http_status(:created)
      expect(agent.sources.sole.source_type).to eq('foto')
    end

    it 'refuses text declared as image/png, so it never reaches tesseract' do
      allow(Autonomia::Agents::Knowledge::Processors::Ocr).to receive(:ler)

      enviar(file: arquivo("/etc/passwd\n/root/.ssh/id_rsa\n"))

      expect_recusa('foto_tipo')
      expect(Autonomia::Agents::Knowledge::Processors::Ocr).not_to have_received(:ler)
    end

    it 'refuses a 14000x14000 png (pixel bomb)' do
      enviar(file: arquivo(png_declarando(14_000, 14_000)))

      expect_recusa('foto_pixels')
    end

    it 'refuses a photo above 5 MB' do
      enviar(file: arquivo(png + ("\x00" * Autonomia::Agents::Config::MAX_IMAGE_BYTES)))

      expect_recusa('foto_tamanho')
    end

    it 'refuses a foto as a media to send' do
      enviar(file: arquivo(png), kind: 'media')

      expect_recusa('foto_so_no_que_sabe')
    end

    it 'refuses a foto for the quote agent (Lia)' do
      lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :draft)
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}/sources",
           params: { source: { source_type: 'foto', reference: 'tabela.png' }, file: arquivo(png) },
           headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.source.foto_agente_de_cotacao'))
      expect(lia.sources.count).to eq(0)
    end
  end

  # A3 — o ActiveStorage aceitaria um signed_id em `file` e anexaria um blob que já existe, até de outra conta.
  it 'refuses a signed_id of a blob from another account instead of a file, for any type' do
    alheio = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('segredo da outra conta'), filename: 'x.txt',
                                                    content_type: 'text/plain')

    enviar(file: alheio.signed_id, source_type: 'txt')

    expect_recusa('file_invalid')
  end

  describe 'read again' do
    let!(:foto) do
      agent.sources.create!(account: account, source_type: 'foto', reference: 'tabela.png', status: :ready)
    end

    it 'refuses to read a foto again outside the Fase 2' do
      post "#{url}/#{foto.id}/resync", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.source.foto_fora_da_fase2'))
    end

    it 'reads a foto again with the Fase 2' do
      Autonomia::Agents::Fase2.ligar!(account)

      expect { post "#{url}/#{foto.id}/resync", headers: administrator.create_new_auth_token }
        .to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)
      expect(response).to have_http_status(:accepted)
    end
  end
end
