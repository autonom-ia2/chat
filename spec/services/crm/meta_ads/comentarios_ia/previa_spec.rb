require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Previa do
  let(:account) { create(:account) }
  let(:fonte) do
    instance_double(Crm::MetaAds::ComentariosIa::Fonte, legenda: 'Bolo de cenoura, receita no e-book')
  end
  let(:classificador) { instance_double(Crm::MetaAds::ComentariosIa::Classificador) }
  let(:previa) { described_class.new(account: account, fonte: fonte, para_quem: 'Quem pedir a receita') }

  def linha(id, text, network: 'instagram', post_id: '1790')
    { id: id, network: network, author: "pessoa.#{id}", text: text, momento: 1.day.ago, post_id: post_id }
  end

  before do
    allow(Crm::MetaAds::ComentariosIa::Classificador).to receive(:new).and_return(classificador)
    allow(classificador).to receive(:decidir!) do |texto|
      { 'Me passa a receita?' => 'private', 'Que lindo!' => 'no_reply', 'Ninguém responde' => 'to_you' }[texto]
    end
  end

  it 'um comentário que receberia e um em que não se aplica, decididos com o "para quem" do dono e a legenda do post' do
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', 'Ninguém responde'), linha('2', 'Que lindo!'),
                                                                         linha('3', 'Me passa a receita?'), linha('4', 'Que lindo!')] })

    expect(previa.call).to eq(status: 'ready', recebe: { author: 'pessoa.3', text: 'Me passa a receita?', network: 'instagram' },
                              nao: { author: 'pessoa.2', text: 'Que lindo!', network: 'instagram' })
    expect(Crm::MetaAds::ComentariosIa::Classificador).to have_received(:new)
      .with(care: an_object_having_attributes(para_quem: 'Quem pedir a receita'), legenda: 'Bolo de cenoura, receita no e-book',
            foto: nil, tela: true)
    expect(classificador).to have_received(:decidir!).exactly(3).times
  end

  # #2454: no anúncio nas duas redes, cada comentário usa a leitura da foto do post da própria rede, como o motor.
  it 'cada comentário decide com a leitura da foto do post da própria rede' do
    Crm::MetaAdsPostReading.create!(account: account, network: 'instagram', post_id: '1790', description: 'Foto no Instagram')
    Crm::MetaAdsPostReading.create!(account: account, network: 'facebook', post_id: '555_888', description: 'Foto no Facebook')
    no_facebook = linha('2', 'Me passa a receita?', network: 'facebook', post_id: '555_888')
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', 'Que lindo!'), no_facebook] })

    previa.call

    expect(Crm::MetaAds::ComentariosIa::Classificador).to have_received(:new).with(hash_including(foto: 'Foto no Instagram')).once
    expect(Crm::MetaAds::ComentariosIa::Classificador).to have_received(:new).with(hash_including(foto: 'Foto no Facebook')).once
  end

  describe 'a resposta dentro de um comentário (#2454)' do
    let(:com_resposta) do
      linha('1', 'Que lindo!').merge(respostas: [{ author: 'pessoa.9', text: 'Me passa a receita?' }])
    end

    before { allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [com_resposta, linha('2', 'Me passa a receita?')] }) }

    it 'com a flag da conversa: uma resposta, decidida com o comentário de cima, aparece dentro dele' do
      account.enable_features!(Crm::MetaAds::ComentariosIa::Cuidar::CONVERSA)

      resultado = previa.call

      expect(resultado[:resposta]).to eq(author: 'pessoa.9', text: 'Me passa a receita?', network: 'instagram', kind: 'recebe',
                                         parent: { id: '1', author: 'pessoa.1', text: 'Que lindo!', network: 'instagram' })
      expect(classificador).to have_received(:decidir!).with('Me passa a receita?', pai: 'Que lindo!')
      # Com o id, a tela põe a resposta dentro do cartão do comentário de cima, sem repetir o de cima.
      expect(resultado[:nao]).to eq(id: '1', author: 'pessoa.1', text: 'Que lindo!', network: 'instagram')
      expect(resultado[:recebe]).to include(id: '2')
    end

    it 'sem a flag: a prévia fica a de antes, sem a resposta' do
      expect(previa.call).not_to have_key(:resposta)
      expect(classificador).not_to have_received(:decidir!).with(anything, pai: anything)
    end
  end

  it 'sem comentário que receberia: um exemplo dito como exemplo; sem "não se aplica": nil' do
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', 'Ninguém responde')] })

    expect(previa.call).to eq(status: 'ready', recebe: { sample: true }, nao: nil)
  end

  it 'lê no máximo LIMITE comentários' do
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: Array.new(15) { |indice| linha(indice.to_s, 'Ninguém responde') } })

    previa.call

    expect(classificador).to have_received(:decidir!).exactly(described_class::LIMITE).times
  end

  it 'IA fora do ar: ai_unavailable, nunca uma prévia vazia que parece "ninguém recebe"' do
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', 'Me passa a receita?')] })
    allow(classificador).to receive(:decidir!).and_raise(Crm::MetaAds::ComentariosIa::Classificador::Indisponivel.new('ai_unavailable'))

    expect(previa.call).to eq(status: 'ai_unavailable')
  end

  it 'leitura que não ficou pronta: devolve o status' do
    allow(fonte).to receive(:ler).and_return({ status: 'meta_unavailable', linhas: [] })

    expect(previa.call).to eq(status: 'meta_unavailable')
  end

  it 'com a flag desligada, o Classificador de verdade barra a IA e a prévia diz que a IA não está disponível' do
    allow(Crm::MetaAds::ComentariosIa::Classificador).to receive(:new).and_call_original
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', 'Me passa a receita?')] })

    expect(previa.call).to eq(status: 'ai_unavailable')
  end
end
