require 'rails_helper'

# IA cuida dos comentários (#2212): o começo da mensagem do passo 1, escrito pela IA uma vez por legenda (decisão do
# Rodrigo no teste real de 30/10: abrir a tela de novo não pode custar outra chamada). O cliente da OpenAI é o de
# verdade, com o HTTP simulado: o uso gravado e o teto são os reais.
RSpec.describe Crm::MetaAds::ComentariosIa::Rascunho do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:url) { 'https://api.openai.com/v1/responses' }
  let(:legenda) { 'E-book de receitas fit por R$ 29. Link na bio, cupom FIT10.' }
  let(:escrito) { 'Oi! Que bom que gostou 😊 O e-book sai por R$ 29 e o cupom FIT10 dá desconto. Quer o link?' }
  let(:feature) { 'meta_ads_comentarios_ia_tela' }

  before do
    account.enable_features!('meta_ads_comentarios_ia')
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
  end

  def openai_responde(offers: true, message: escrito, texto: nil)
    corpo = texto || { offers: offers, message: message }.to_json
    stub_request(:post, url).to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { id: 'resp_1', output_text: corpo, usage: { input_tokens: 500, output_tokens: 80 } }.to_json
    )
  end

  def rascunho(texto = legenda, post_id: '17900000000000001', conta: account)
    described_class.new(account: conta, target_kind: 'post', target_id: post_id, legenda: texto).call
  end

  def usos
    Crm::AiUsageEvent.where(account_id: account.id, feature: feature)
  end

  it 'escreve o começo a partir da legenda, guarda com o digest e grava o uso no teto da tela' do
    openai_responde

    expect(rascunho).to eq(status: 'ready', message: escrito)
    expect(a_request(:post, url).with { |req| req.body.include?('E-book de receitas fit por R$ 29') }).to have_been_made.once
    expect(Crm::MetaAdsCommentDraft.sole).to have_attributes(account_id: account.id, target_kind: 'post', status: 'ready', message: escrito)
    expect(usos.count).to eq(1)
  end

  it 'abrir de novo com a mesma legenda não chama a IA' do
    openai_responde
    rascunho

    expect(rascunho).to eq(status: 'ready', message: escrito)
    expect(a_request(:post, url)).to have_been_made.once
  end

  it 'legenda nova chama a IA de novo e troca o guardado (sem linha nova)' do
    openai_responde
    rascunho
    openai_responde(message: 'Oi! Agora sai por R$ 19. Quer o link?')

    expect(rascunho('E-book por R$ 19 só esta semana.')).to eq(status: 'ready', message: 'Oi! Agora sai por R$ 19. Quer o link?')
    expect(a_request(:post, url)).to have_been_made.twice
    expect(Crm::MetaAdsCommentDraft.sole.message).to eq('Oi! Agora sai por R$ 19. Quer o link?')
  end

  it 'post que não oferece nada: campo vazio, guardado para não perguntar de novo' do
    openai_responde(offers: false, message: '')

    expect(rascunho).to eq(status: 'no_offer')
    expect(rascunho).to eq(status: 'no_offer')
    expect(a_request(:post, url)).to have_been_made.once
  end

  it 'resposta que não serve (vazia, longa demais ou JSON quebrado): campo vazio, guardado, sem nova chamada' do
    [{ message: '  ' }, { message: 'a' * (described_class::CHARACTER_LIMIT + 1) }, { texto: 'não é json' }].each_with_index do |caso, indice|
      openai_responde(**caso)
      post_id = "1790000000000010#{indice}"

      expect(rascunho(post_id: post_id)).to eq(status: 'no_offer')
      expect(rascunho(post_id: post_id)).to eq(status: 'no_offer')
      expect(Crm::MetaAdsCommentDraft.find_by(target_id: post_id).status).to eq('invalid')
    end
    expect(a_request(:post, url)).to have_been_made.times(3)
  end

  it 'IA sem resposta: uma ida só, sem nova tentativa; a tentativa conta no teto e só volta depois de 10 minutos' do
    stub_request(:post, url).to_timeout

    expect(rascunho).to eq(status: 'ai_unavailable')
    expect(a_request(:post, url)).to have_been_made.once
    expect(usos.count).to eq(1)
    expect(Crm::MetaAdsCommentDraft.sole.status).to eq('failed')

    expect(rascunho).to eq(status: 'ai_unavailable')
    expect(a_request(:post, url)).to have_been_made.once

    travel 11.minutes do
      openai_responde
      expect(rascunho).to eq(status: 'ready', message: escrito)
    end
  end

  it 'erro 503 da OpenAI: sem nova tentativa (a chamada roda dentro da requisição)' do
    stub_request(:post, url).to_return(status: 503, body: { error: { message: 'fora' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(rascunho).to eq(status: 'ai_unavailable')
    expect(a_request(:post, url)).to have_been_made.once
  end

  it 'outra abertura está escrevendo (reserva recente): não chama de novo; reserva parada há mais de 1 minuto é retomada' do
    openai_responde
    rascunho
    Crm::MetaAdsCommentDraft.sole.update!(status: 'writing', message: nil)

    expect(rascunho).to eq(status: 'ai_unavailable')
    expect(a_request(:post, url)).to have_been_made.once

    travel 2.minutes do
      expect(rascunho).to eq(status: 'ready', message: escrito)
    end
    expect(a_request(:post, url)).to have_been_made.twice
  end

  it 'duas aberturas juntas: só quem reservou chama a IA (compare-and-set do que foi lido)' do
    openai_responde
    rascunho
    lido = Crm::MetaAdsCommentDraft.sole
    # A outra abertura já reservou a legenda nova depois desta ler a linha.
    # rubocop:disable Rails/SkipsModelValidations -- simula a outra abertura gravando direto, como o compare-and-set faz
    Crm::MetaAdsCommentDraft.where(id: lido.id).update_all(caption_digest: 'outra', status: 'writing', updated_at: 1.second.from_now)
    # rubocop:enable Rails/SkipsModelValidations
    allow(Crm::MetaAdsCommentDraft).to receive(:find_by).and_return(lido)

    expect(rascunho('Legenda nova')).to eq(status: 'ai_unavailable')
    expect(a_request(:post, url)).to have_been_made.once
  end

  it 'flag do cuidado desligada: não chama a IA' do
    account.disable_features!('meta_ads_comentarios_ia')
    openai_responde

    expect(rascunho).to eq(status: 'ai_unavailable')
    expect(a_request(:post, url)).not_to have_been_made
  end

  it 'no teto do dia da tela: não chama a IA; o já guardado continua valendo' do
    openai_responde
    rascunho(post_id: '17900000000000009')
    teto = Crm::MetaAds::ComentariosIa::Classificador::TETO_DIARIO_DA_TELA
    # rubocop:disable Rails/SkipsModelValidations -- enche o teto do dia sem 300 chamadas
    Crm::AiUsageEvent.insert_all(Array.new(teto) { { account_id: account.id, feature: feature, model: 'x', created_at: Time.current } })
    # rubocop:enable Rails/SkipsModelValidations

    expect(rascunho).to eq(status: 'ai_unavailable')
    expect(rascunho(post_id: '17900000000000009')).to eq(status: 'ready', message: escrito)
    expect(a_request(:post, url)).to have_been_made.once
  end

  it 'sem legenda: não chama a IA nem guarda nada' do
    expect(rascunho('  ')).to eq(status: 'no_caption')
    expect(Crm::MetaAdsCommentDraft.count).to eq(0)
  end

  it 'CRM_AI desligado: não chama a IA' do
    openai_responde

    with_modified_env CRM_AI_ENABLED: 'false' do
      expect(rascunho).to eq(status: 'ai_unavailable')
    end
    expect(a_request(:post, url)).not_to have_been_made
  end

  it 'um post não usa o guardado de outro, nem de outra conta' do
    openai_responde
    rascunho
    outra = create(:account)
    Crm::MetaAdsCommentDraft.create!(account: outra, target_kind: 'post', target_id: '17900000000000002',
                                     caption_digest: 'x', status: 'ready', message: 'De outra conta')

    expect(rascunho(post_id: '17900000000000002')).to eq(status: 'ready', message: escrito)
    expect(a_request(:post, url)).to have_been_made.twice
  end
end
