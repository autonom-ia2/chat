require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Resumo do
  let(:account) { create(:account) }
  let(:alvo) { { 'kind' => 'post', 'perfil' => 'ig-1', 'post_id' => '1790' } }
  let(:fonte) { instance_double(Crm::MetaAds::ComentariosIa::Fonte) }
  let(:classificador) { instance_double(Crm::MetaAds::ComentariosIa::Classificador) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:resumo) { described_class.new(account: account, alvo: alvo, fonte: fonte) }
  let(:linhas) do
    [linha('1', 'Quanto custa?'), linha('2', 'Tem no M?'), linha('3', 'Ninguém me responde'), linha('4', 'Lindo!'),
     linha('5', 'Valor?', dias: 9)]
  end

  def linha(id, text, dias: 1)
    { id: id, network: 'instagram', author: 'pessoa', text: text, momento: dias.days.ago }
  end

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: linhas })
    allow(Crm::MetaAds::ComentariosIa::Classificador).to receive(:new).and_return(classificador)
    allow(classificador).to receive(:decidir!) do |texto|
      { 'Quanto custa?' => 'price', 'Tem no M?' => 'private', 'Ninguém me responde' => 'to_you', 'Lindo!' => 'no_reply',
        'Valor?' => 'price' }[texto]
    end
  end

  it 'na primeira vez, conta fora do pedido e diz que está lendo, com um job só' do
    expect { 2.times { expect(resumo.call).to eq(status: 'reading') } }
      .to have_enqueued_job(Crm::MetaAds::ComentariosIa::ResumoJob).with(account.id, alvo).exactly(:once)
    expect(classificador).not_to have_received(:decidir!)
  end

  it 'conta os pedidos de até 7 dias, os mais velhos e as reclamações, e devolve do cache depois' do
    resumo.contar!

    expect(resumo.call).to eq(status: 'ready', questions: 2, questions_old: 1, complaints: 1, read: 5, more: false)
  end

  it 'com o critério fixo do resumo no lugar do "para quem" do dono' do
    resumo.contar!

    expect(Crm::MetaAds::ComentariosIa::Classificador).to have_received(:new)
      .with(care: an_object_having_attributes(account: account, para_quem: described_class::CRITERIO, offer: nil))
  end

  it 'lista nova (alguém respondeu ou chegou comentário): conta de novo' do
    resumo.contar!
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: linhas.first(2) })

    expect(resumo.call).to eq(status: 'reading')
  end

  it 'mais comentários do que o limite: conta os mais recentes e diz que há mais' do
    muitas = Array.new(described_class::LIMITE + 1) { |indice| linha(indice.to_s, 'Lindo!') }
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: muitas })

    resumo.contar!

    expect(resumo.call).to include(read: described_class::LIMITE, more: true)
    expect(classificador).to have_received(:decidir!).exactly(described_class::LIMITE).times
  end

  it 'leitura que não ficou pronta: devolve o status, sem contar' do
    allow(fonte).to receive(:ler).and_return({ status: 'needs_permission', linhas: [] })

    expect(resumo.call).to eq(status: 'needs_permission')
    expect(classificador).not_to have_received(:decidir!)
  end

  describe 'com o Jev fora do ar' do
    before do
      allow(classificador).to receive(:decidir!).and_raise(TypesafeAi::Decisor::Error.new('typesafe_unavailable'))
    end

    it 'não grava conta zerada como pronta: diz ai_unavailable uma vez e, na próxima, conta de novo' do
      expect(resumo.call).to eq(status: 'reading')
      resumo.contar!

      expect(resumo.call).to eq(status: 'ai_unavailable')
      expect { expect(resumo.call).to eq(status: 'reading') }.to have_enqueued_job(Crm::MetaAds::ComentariosIa::ResumoJob)
    end

    it 'para no primeiro erro, sem gastar as outras chamadas' do
      resumo.contar!

      expect(classificador).to have_received(:decidir!).once
    end
  end

  it 'a trava do "contando" dura mais que o job mais lento: uma chamada ao Jev por comentário, com as tentativas' do
    cliente = TypesafeAi::Client
    por_comentario = (cliente::OPEN_TIMEOUT + cliente::READ_TIMEOUT) * (cliente::MAX_RETRIES + 1)

    expect(described_class::CONTANDO).to be >= (described_class::LIMITE * por_comentario).seconds
  end

  it 'perfil ou conexão que não existem mais: not_found' do
    expect(described_class.new(account: account, alvo: alvo).call).to eq(status: 'not_found')
  end

  it 'no cache só os números, nunca o texto' do
    resumo.contar!

    gravado = cache.instance_variable_get(:@data).values.map { |entrada| entrada.value.to_s }.join
    expect(gravado).not_to include('Quanto custa', 'Ninguém', 'pessoa')
  end
end
