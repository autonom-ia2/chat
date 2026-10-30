require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Fonte do
  def row(id, page: false, created: '2026-10-29T10:00:00+0000', **mudancas)
    { id: id, author: { name: nil, username: "pessoa.#{id}", is_page: page }, text: 'Quanto custa?', created_time: created,
      hidden: false, replies: [], private_reply: nil }.merge(mudancas)
  end

  def fonte(**leituras)
    described_class.new(leituras.transform_keys(&:to_s).transform_values { |payload| { ler: -> { payload }, inbox_id: 3, post_id: '1790' } })
  end

  it 'só os comentários que esperam o dono: de outra pessoa, à mostra, sem resposta da conta e sem privado' do
    comments = [
      row('1'), row('2', page: true), row('3', hidden: true), row('4', replies: [row('4r', page: true)]),
      row('5', private_reply: { sent_at: 'x' }), row('6', text: ''), row('7', replies: [row('7r')])
    ]

    lido = fonte(instagram: { status: 'ready', comments: comments }).ler

    expect(lido[:status]).to eq('ready')
    expect(lido[:linhas].pluck(:id)).to eq(%w[1 7])
    expect(lido[:linhas].first).to include(network: 'instagram', author: 'pessoa.1', text: 'Quanto custa?', inbox_id: 3, post_id: '1790')
    expect(lido[:linhas].first.keys).not_to include(:espera, :escondida)
    expect(lido[:escondidas].pluck(:id)).to eq(%w[3])
  end

  it 'anúncio nas duas redes: junta as listas, do mais novo para o mais velho' do
    lido = fonte(instagram: { status: 'ready', comments: [row('ig', created: '2026-10-28T10:00:00+0000')] },
                 facebook: { status: 'ready', comments: [row('fb', created: '2026-10-29T10:00:00+0000')] }).ler

    expect(lido[:linhas].map { |linha| [linha[:network], linha[:id]] }).to eq([%w[facebook fb], %w[instagram ig]])
  end

  it 'leitura que não ficou pronta: devolve o status, sem linhas' do
    expect(fonte(instagram: { status: 'needs_permission', comments: [] }).ler).to eq(status: 'needs_permission', linhas: [], escondidas: [])
  end

  it 'erro da Meta vira o status do erro' do
    leitura = -> { raise Crm::MetaAds::InstagramPrivateReply::Error, 'meta_unavailable' }

    expect(described_class.new({ 'instagram' => { ler: leitura } }).ler).to eq(status: 'meta_unavailable', linhas: [], escondidas: [])
  end

  describe '.anuncio (#2212, B2)' do
    let(:connection) { instance_double(Crm::MetaAdsConnection) }
    let(:ig_inbox) { instance_double(Inbox, id: 11) }
    let(:fb_inbox) { instance_double(Inbox, id: 12) }
    let(:anuncio) do
      instance_double(Crm::MetaAds::ComentariosIa::Anuncio, connection: connection, ad_id: '120',
                                                            redes: { 'instagram' => { post_id: '1790', inbox: ig_inbox },
                                                                     'facebook' => { post_id: '55_77', inbox: fb_inbox } })
    end

    before do
      instagram = instance_double(Crm::MetaAds::InstagramComments, payload: { status: 'ready', comments: [row('ig')] })
      facebook = instance_double(Crm::MetaAds::FacebookComments, list: { status: 'ready', comments: [row('55_9')] })
      allow(Crm::MetaAds::InstagramComments).to receive(:new).and_return(instagram)
      allow(Crm::MetaAds::FacebookComments).to receive(:new).and_return(facebook)
    end

    it 'cada linha leva a caixa e o post do criativo da rede dela, para o "Ler e mandar" pôr na fila do motor' do
      linhas = described_class.anuncio(anuncio, %w[instagram facebook]).ler[:linhas]

      expect(linhas.map { |linha| linha.slice(:id, :network, :inbox_id, :post_id) }).to contain_exactly(
        { id: 'ig', network: 'instagram', inbox_id: 11, post_id: '1790' }, { id: '55_9', network: 'facebook', inbox_id: 12, post_id: '55_77' }
      )
    end

    it 'só as redes pedidas no alvo' do
      linhas = described_class.anuncio(anuncio, %w[instagram]).ler[:linhas]

      expect(linhas.pluck(:network)).to eq(%w[instagram])
      expect(Crm::MetaAds::FacebookComments).not_to have_received(:new)
    end

    it 'do alvo: lê o anúncio de novo pela conexão da conta; anúncio que sumiu, nil' do
      account = create(:account)
      allow(Crm::MetaAdsConnection).to receive(:find_by).with(account_id: account.id).and_return(connection)
      allow(Crm::MetaAds::ComentariosIa::Anuncio).to receive(:ler).with(connection, '120').and_return(anuncio, nil)
      alvo = { 'kind' => 'ad', 'ad_id' => '120', 'networks' => %w[facebook], 'post_ids' => %w[55_77] }

      expect(described_class.do_alvo(account, alvo).ler[:linhas].pluck(:inbox_id)).to eq([12])
      expect(described_class.do_alvo(account, alvo)).to be_nil
    end
  end
end
