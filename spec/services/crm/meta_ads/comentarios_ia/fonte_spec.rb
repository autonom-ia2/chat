require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Fonte do
  def row(id, page: false, created: '2026-10-29T10:00:00+0000', **mudancas)
    { id: id, author: { name: nil, username: "pessoa.#{id}", is_page: page }, text: 'Quanto custa?', created_time: created,
      hidden: false, replies: [], private_reply: nil }.merge(mudancas)
  end

  def fonte(**leituras)
    described_class.new(leituras.transform_keys(&:to_s).transform_values { |payload| -> { payload } })
  end

  it 'só os comentários que esperam o dono: de outra pessoa, à mostra, sem resposta da conta e sem privado' do
    comments = [
      row('1'), row('2', page: true), row('3', hidden: true), row('4', replies: [row('4r', page: true)]),
      row('5', private_reply: { sent_at: 'x' }), row('6', text: ''), row('7', replies: [row('7r')])
    ]

    lido = fonte(instagram: { status: 'ready', comments: comments }).ler

    expect(lido[:status]).to eq('ready')
    expect(lido[:linhas].pluck(:id)).to eq(%w[1 7])
    expect(lido[:linhas].first).to include(network: 'instagram', author: 'pessoa.1', text: 'Quanto custa?')
  end

  it 'anúncio nas duas redes: junta as listas, do mais novo para o mais velho' do
    lido = fonte(instagram: { status: 'ready', comments: [row('ig', created: '2026-10-28T10:00:00+0000')] },
                 facebook: { status: 'ready', comments: [row('fb', created: '2026-10-29T10:00:00+0000')] }).ler

    expect(lido[:linhas].map { |linha| [linha[:network], linha[:id]] }).to eq([%w[facebook fb], %w[instagram ig]])
  end

  it 'leitura que não ficou pronta: devolve o status, sem linhas' do
    expect(fonte(instagram: { status: 'needs_permission', comments: [] }).ler).to eq(status: 'needs_permission', linhas: [])
  end

  it 'erro da Meta vira o status do erro' do
    leitura = -> { raise Crm::MetaAds::InstagramPrivateReply::Error, 'meta_unavailable' }

    expect(described_class.new({ 'instagram' => leitura }).ler).to eq(status: 'meta_unavailable', linhas: [])
  end

  it 'erro da leitura do Facebook (anúncio e Página do Seus posts) também vira o status, sem subir' do
    [Crm::MetaAds::FacebookComments::Error, SeusPosts::ComentariosPagina::Error].each do |erro|
      leitura = -> { raise erro, 'meta_unavailable' }

      expect(described_class.new({ 'facebook' => leitura }).ler).to eq(status: 'meta_unavailable', linhas: [])
    end
  end
end
