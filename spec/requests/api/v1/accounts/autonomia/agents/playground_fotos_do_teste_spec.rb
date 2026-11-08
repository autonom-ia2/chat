require 'rails_helper'

# #1427 — a foto mandada no Testar da página do agente. Na Fase 2 ela passa pelas conferências da foto do material
# (FotoConferida: tipo pelos bytes, 5 MB, 40 MP, sem animada) e a recusada responde 422 com o motivo. Fora da Fase 2 e na
# Lia, como na main. Em todos os casos a foto vale só no teste: vai ao modelo neste turno e não cria conversa, mensagem,
# anexo, material nem trecho da base.
RSpec.describe 'Autonomia agent playground - foto do teste', type: :request do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }).tap { |conta| Autonomia::Agents::Fase2.ligar!(conta) }
  end
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support', status: :active,
                                     instruction: 'Você atende a lanchonete da Bia.')
  end
  let(:png) { Rails.root.join('spec/fixtures/files/autonomia/foto_da_criacao/cardapio-legivel.png').binread }
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/test" }
  let(:cliente_de_ia) do
    instance_double(Crm::Ai::ResponsesClient,
                    create_with_tool_executor: { text: { reply: 'Pela foto, é o X-Salada.', confidence: 0.95, should_handoff: false,
                                                         used_snippet_ids: [], answered_from_knowledge: false }.to_json })
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential'))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente_de_ia)
    allow(Autonomia::Agents::Retriever).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::Retriever, retrieve: []))
  end

  def data_url(bytes, tipo: 'image/png')
    "data:#{tipo};base64,#{Base64.strict_encode64(bytes)}"
  end

  def png_declarando(largura, altura)
    ["\x89PNG\r\n\x1a\n", [13].pack('N'), 'IHDR', [largura, altura].pack('NN'), "\x08\x02\x00\x00\x00", "\x00" * 64].map(&:b).join
  end

  def gif_animado
    quadro = [',', [0, 0, 1, 1].pack('vvvv'), "\x00\x02\x01\x00\x00"].map(&:b).join
    ['GIF89a', [1, 1].pack('vv'), "\x00\x00\x00", quadro, quadro, ';'].map(&:b).join
  end

  def testar(images)
    post url, params: { message: 'Quanto custa este?', images: images }, headers: administrator.create_new_auth_token, as: :json
  end

  def pedido
    Crm::Ai::InteractiveRequest.read(response.parsed_body['id'])
  end

  def expect_recusa(chave)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t(chave, max: Autonomia::Agents::Config::MAX_IMAGES_PER_MESSAGE))
    expect(response.parsed_body['error']).not_to include('Translation missing')
    expect(response.parsed_body['code']).to eq('foto_recusada')
  end

  describe 'in the Fase 2' do
    it 'sends a real photo to the model, with the type read from the bytes' do
      testar([data_url(png, tipo: 'image/jpeg')])

      expect(response).to have_http_status(:accepted)
      expect(pedido.dig('inputs', 'images')).to eq([data_url(png, tipo: 'image/png')])
    end

    it 'refuses text declared as a photo' do
      testar([data_url("Pastel R$ 8,00\n")])

      expect_recusa('autonomia.source.foto_tipo')
    end

    it 'refuses what is not a base64 data-url' do
      testar(['https://example.com/foto.png'])

      expect_recusa('autonomia.source.foto_tipo')
    end

    it 'refuses a photo above 5 MB without decoding it' do
      testar([data_url(png + ("\x00" * Autonomia::Agents::Config::MAX_IMAGE_BYTES))])

      expect_recusa('autonomia.source.foto_tamanho')
    end

    it 'refuses a photo above 40 megapixels' do
      testar([data_url(png_declarando(8000, 8000))])

      expect_recusa('autonomia.source.foto_pixels')
    end

    it 'refuses an animated photo with the sentence of the test' do
      testar([data_url(gif_animado, tipo: 'image/gif')])

      expect_recusa('autonomia.teste.foto_animada')
    end

    it 'refuses more photos than one question takes' do
      testar([data_url(png)] * (Autonomia::Agents::Config::MAX_IMAGES_PER_MESSAGE + 1))

      expect_recusa('autonomia.teste.foto_muitas')
    end

    it 'refuses the whole question when one of the photos fails, sending nothing to the model' do
      expect { testar([data_url(png), data_url('texto')]) }.not_to have_enqueued_job(Crm::Ai::InteractiveJob)

      expect_recusa('autonomia.source.foto_tipo')
    end

    it 'answers about the photo without creating a conversation, message, attachment, material or knowledge entry' do
      contagens = -> { [Conversation, Message, Attachment, Autonomia::Agents::Source, Autonomia::Agents::KnowledgeEntry].map(&:count) }

      administrator
      agent
      expect do
        testar([data_url(png)])
        Crm::Ai::InteractiveJob.perform_now(response.parsed_body['id'])
      end.not_to change(contagens, :call)

      expect(pedido['status']).to eq('done')
      expect(pedido.dig('result', 'reply')).to eq('Pela foto, é o X-Salada.')
      expect(cliente_de_ia).to have_received(:create_with_tool_executor) do |**argumentos|
        expect(argumentos.to_json).to include(Base64.strict_encode64(png))
      end
    end
  end

  describe 'the Lia (instruction kept) in the Fase 2' do
    let(:lia) do
      Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Sena').call
    end

    it 'keeps the rule of the main: no 422, the declared type only' do
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}/test",
           params: { message: 'Quanto custa este?', images: [data_url("Pastel R$ 8,00\n"), data_url(png)] },
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:accepted)
      expect(pedido.dig('inputs', 'images')).to eq([data_url("Pastel R$ 8,00\n"), data_url(png)])
    end
  end

  # O log do Rails não leva as fotos (o Sentry tem o filtro próprio, no SentryHttpAuthScrubber).
  it 'keeps the photos out of the Rails log' do
    filtro = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(filtro.filter('message' => 'Oi', 'images' => [data_url(png)])).to eq('message' => 'Oi', 'images' => '[FILTERED]')
  end

  describe 'outside the Fase 2' do
    before { Autonomia::Agents::Fase2.desligar!(account) }

    it 'keeps the check of the main: only the declared type, so text declared as a photo still goes to the model' do
      testar([data_url("Pastel R$ 8,00\n"), data_url(png)])

      expect(response).to have_http_status(:accepted)
      expect(pedido.dig('inputs', 'images')).to eq([data_url("Pastel R$ 8,00\n"), data_url(png)])
    end
  end
end
