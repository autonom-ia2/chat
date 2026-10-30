require 'rails_helper'

# IA cuida dos comentários (#2212): o começo da mensagem do passo 1, escrito pela IA uma vez por legenda (decisão do
# Rodrigo no teste real de 30/10: abrir a tela de novo não pode custar outra chamada).
RSpec.describe Crm::MetaAds::ComentariosIa::Rascunho do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:credential) { { api_key: 'synthetic-test-key', source: :system } }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:legenda) { 'E-book de receitas fit por R$ 29. Link na bio, cupom FIT10.' }
  let(:escrito) { 'Oi! Que bom que gostou 😊 O e-book sai por R$ 29 e o cupom FIT10 dá desconto. Quer o link?' }

  before do
    account.enable_features!('meta_ads_comentarios_ia')
    allow(Crm::Ai::CredentialResolver).to receive(:new).with(account: account)
                                                       .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: credential))
    allow(Crm::Ai::ResponsesClient).to receive(:new)
      .with(credential: credential, feature: 'meta_ads_comentarios_ia_tela', account: account).and_return(client)
  end

  def responde(offers: true, message: escrito)
    allow(client).to receive(:create).and_return({ text: { offers: offers, message: message }.to_json })
  end

  def rascunho(texto = legenda, post_id: '17900000000000001')
    described_class.new(account: account, target_kind: 'post', target_id: post_id, legenda: texto).call
  end

  it 'escreve o começo a partir da legenda e o guarda com o digest dela' do
    responde

    expect(rascunho).to eq(status: 'ready', message: escrito)
    expect(client).to have_received(:create).with(hash_including(input: { language: 'pt_BR', caption: legenda }.to_json)).once
    expect(Crm::MetaAdsCommentDraft.sole).to have_attributes(account_id: account.id, target_kind: 'post', message: escrito)
  end

  it 'abrir de novo com a mesma legenda não chama a IA' do
    responde
    rascunho

    expect(rascunho).to eq(status: 'ready', message: escrito)
    expect(client).to have_received(:create).once
  end

  it 'legenda nova chama a IA de novo e troca o guardado (sem linha nova)' do
    responde
    rascunho
    responde(message: 'Oi! Agora sai por R$ 19. Quer o link?')

    expect(rascunho('E-book por R$ 19 só esta semana.')).to eq(status: 'ready', message: 'Oi! Agora sai por R$ 19. Quer o link?')
    expect(client).to have_received(:create).twice
    expect(Crm::MetaAdsCommentDraft.sole.message).to eq('Oi! Agora sai por R$ 19. Quer o link?')
  end

  it 'post que não oferece nada: campo vazio, guardado para não perguntar de novo' do
    responde(offers: false, message: '')

    expect(rascunho).to eq(status: 'no_offer')
    expect(rascunho).to eq(status: 'no_offer')
    expect(client).to have_received(:create).once
  end

  it 'sem legenda: não chama a IA' do
    allow(client).to receive(:create)

    expect(rascunho('  ')).to eq(status: 'no_caption')
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'IA fora do ar: ai_unavailable e nada guardado (a próxima abertura tenta de novo)' do
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error.new('timeout'))

    expect(rascunho).to eq(status: 'ai_unavailable')
    expect(Crm::MetaAdsCommentDraft.count).to eq(0)
  end

  it 'resposta que não serve (vazia, longa demais ou JSON quebrado): ai_unavailable, nada guardado' do
    responde(message: '  ')
    expect(rascunho).to eq(status: 'ai_unavailable')
    responde(message: 'a' * (described_class::CHARACTER_LIMIT + 1))
    expect(rascunho).to eq(status: 'ai_unavailable')
    allow(client).to receive(:create).and_return({ text: 'não é json' })
    expect(rascunho).to eq(status: 'ai_unavailable')

    expect(Crm::MetaAdsCommentDraft.count).to eq(0)
  end

  it 'flag do cuidado desligada: não chama a IA' do
    account.disable_features!('meta_ads_comentarios_ia')
    allow(client).to receive(:create)

    expect(rascunho).to eq(status: 'ai_unavailable')
    expect(client).not_to have_received(:create)
  end

  it 'conta no teto do dia da tela: no teto, não chama a IA; o guardado continua valendo' do
    responde
    rascunho(post_id: '17900000000000009')
    teto = Crm::MetaAds::ComentariosIa::Classificador::TETO_DIARIO_DA_TELA
    allow(Crm::AiUsageEvent).to receive(:where).and_return(instance_double(ActiveRecord::Relation, count: teto))

    expect(rascunho).to eq(status: 'ai_unavailable')
    expect(rascunho(post_id: '17900000000000009')).to eq(status: 'ready', message: escrito)
    expect(client).to have_received(:create).once
  end

  it 'CRM_AI desligado: não chama a IA' do
    allow(client).to receive(:create)

    with_modified_env CRM_AI_ENABLED: 'false' do
      expect(rascunho).to eq(status: 'ai_unavailable')
    end
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'um post não usa o guardado de outro, nem de outra conta' do
    responde
    rascunho
    outra = create(:account)
    Crm::MetaAdsCommentDraft.create!(account: outra, target_kind: 'post', target_id: '17900000000000002',
                                     caption_digest: 'x', message: 'De outra conta')

    expect(rascunho(post_id: '17900000000000002')).to eq(status: 'ready', message: escrito)
    expect(client).to have_received(:create).twice
  end
end
