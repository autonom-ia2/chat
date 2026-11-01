require 'rails_helper'

# #2454: "O que eu vi na foto". Uma leitura por post, só depois do clique do dono; a correção do dono vale no lugar dela.
# A chave é sempre a da conta. Meta ou IA fora do ar não quebra a tela: "não consegui ver agora".
RSpec.describe Crm::MetaAds::ComentariosIa::Foto do
  let(:account) { create(:account) }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:urls) { ['https://cdn.exemplo/1.jpg'] }
  let(:imagens) { -> { urls } }

  def foto(post_id: '1790', conta: account, ler: imagens, com_cliente: cliente)
    described_class.new(account: conta, network: 'instagram', post_id: post_id, imagens: ler, cliente: com_cliente)
  end

  def responde(descricao = 'Um vestido azul de linho num cabide.')
    allow(cliente).to receive(:create).and_return({ text: { description: descricao }.to_json })
  end

  def pedido
    pedido = nil
    expect(cliente).to have_received(:create) { |**argumentos| pedido = argumentos }
    pedido
  end

  before do
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
  end

  it 'lê a foto numa chamada só, com detalhe baixo, e grava a leitura do post' do
    responde

    expect(foto.ler).to eq(status: 'ready', text: 'Um vestido azul de linho num cabide.', corrected: false)
    expect(cliente).to have_received(:create).once
    imagem = pedido[:input].first[:content].find { |parte| parte[:type] == 'input_image' }
    expect(imagem).to eq(type: 'input_image', image_url: 'https://cdn.exemplo/1.jpg', detail: 'low')
    expect(Crm::MetaAdsPostReading.sole).to have_attributes(account_id: account.id, network: 'instagram', post_id: '1790',
                                                            description: 'Um vestido azul de linho num cabide.')
  end

  it 'a segunda vez lê do banco, sem chamar a IA nem a Meta' do
    responde
    foto.ler
    ler_de_novo = -> { raise 'não devia ler a Meta' }

    expect(foto(ler: ler_de_novo).ler).to include(status: 'ready', text: 'Um vestido azul de linho num cabide.')
    expect(cliente).to have_received(:create).once
  end

  it 'carrossel: as imagens juntas, numa chamada só' do
    urls.push('https://cdn.exemplo/2.jpg', 'https://cdn.exemplo/3.jpg')
    responde('Três fotos do mesmo vestido, de frente, de lado e de costas.')

    foto.ler

    enviadas = pedido[:input].first[:content].select { |parte| parte[:type] == 'input_image' }.pluck(:image_url)
    expect(enviadas).to eq(%w[https://cdn.exemplo/1.jpg https://cdn.exemplo/2.jpg https://cdn.exemplo/3.jpg])
    expect(cliente).to have_received(:create).once
  end

  it 'a imagem é dado, nunca instrução: as instruções dizem isso e pedem português' do
    responde

    foto.ler

    expect(pedido[:instructions]).to include('data', 'never', 'Brazilian Portuguese')
    expect(pedido[:instructions]).not_to include('cdn.exemplo', 'https://')
    expect(pedido[:input].to_json).to include('https://cdn.exemplo/1.jpg')
  end

  describe 'duas aberturas juntas (a linha é reservada antes da IA)' do
    it 'a segunda abertura, com a primeira lendo, não chama a IA' do
      Crm::MetaAdsPostReading.create!(account: account, network: 'instagram', post_id: '1790')
      allow(cliente).to receive(:create)

      expect(foto.ler).to eq(status: 'unavailable')
      expect(cliente).not_to have_received(:create)
    end

    it 'só uma das duas chama a IA, mesmo começando juntas' do
      chamadas = 0
      allow(cliente).to receive(:create) do
        chamadas += 1
        # A segunda abertura entra enquanto a primeira espera a IA.
        foto.ler if chamadas == 1
        { text: { description: 'Um vestido azul.' }.to_json }
      end

      expect(foto.ler).to include(status: 'ready', text: 'Um vestido azul.')
      expect(chamadas).to eq(1)
    end

    it 'reserva parada (o processo morreu) vence: a próxima abertura lê' do
      Crm::MetaAdsPostReading.create!(account: account, network: 'instagram', post_id: '1790', updated_at: 2.minutes.ago)
      responde

      expect(foto.ler).to include(status: 'ready')
      expect(cliente).to have_received(:create).once
    end

    it 'a IA que não respondeu solta a reserva: a próxima abertura tenta de novo' do
      allow(cliente).to receive(:create).and_return({ text: 'sem formato' })

      expect(foto.ler).to eq(status: 'unavailable')
      expect(Crm::MetaAdsPostReading.count).to eq(0)
    end
  end

  it 'a correção do dono vence a leitura, e quem corrigiu fica gravado' do
    responde
    foto.ler
    dono = create(:user, account: account)

    expect(foto.corrigir!('Vestido midi azul-marinho, tamanhos P ao G', user: dono))
      .to eq(status: 'ready', text: 'Vestido midi azul-marinho, tamanhos P ao G', corrected: true)
    expect(described_class.texto_para_ia(account, 'instagram', '1790')).to eq('Vestido midi azul-marinho, tamanhos P ao G')
    expect(Crm::MetaAdsPostReading.sole.corrected_by).to eq(dono)
  end

  it 'corrigir sem leitura antes (a IA não viu): a correção vale sozinha, sem chamar a IA' do
    allow(cliente).to receive(:create)
    foto.corrigir!('Bolo de cenoura com cobertura', user: create(:user, account: account))

    expect(foto.ler).to eq(status: 'ready', text: 'Bolo de cenoura com cobertura', corrected: true)
    expect(cliente).not_to have_received(:create)
  end

  it 'apagar a correção volta para a leitura da IA' do
    responde
    foto.ler
    foto.corrigir!('Outra coisa', user: nil)

    expect(foto.corrigir!('  ', user: nil)).to include(text: 'Um vestido azul de linho num cabide.', corrected: false)
  end

  it 'correção acima do limite é recusada' do
    expect { foto.corrigir!('a' * (Crm::MetaAdsPostReading::TEXT_LIMIT + 1), user: nil) }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'sem imagem no post: não chama a IA e não grava' do
    allow(cliente).to receive(:create)

    expect(foto(ler: -> { [] }).ler).to eq(status: 'no_image')
    expect(cliente).not_to have_received(:create)
    expect(Crm::MetaAdsPostReading.count).to eq(0)
  end

  describe 'a chave é sempre a da conta' do
    before { allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente) }

    it 'com a chave da conta (hook crm_kanban_ai): pergunta com a feature própria' do
      allow(Crm::Ai::CredentialResolver).to receive(:new)
        .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', source: :hook }))
      responde

      foto(com_cliente: nil).ler

      expect(Crm::Ai::ResponsesClient).to have_received(:new)
        .with(hash_including(feature: described_class::FEATURE, account: account, max_retries: 0))
    end

    it 'sem chave da conta (nenhuma, ou só a da instalação): fica vazio, sem chamar a IA nem gravar' do
      [nil, { api_key: 'k', source: :system }].each do |credencial|
        allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: credencial))

        expect(foto(com_cliente: nil).ler).to eq(status: 'no_credential')
      end
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
      expect(Crm::MetaAdsPostReading.count).to eq(0)
    end
  end

  describe 'nada quebra a tela' do
    it 'a IA fora do ar: não consegui ver agora, sem gravar, e a próxima abertura tenta de novo' do
      allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error.new('fora', status: 503))

      expect(foto.ler).to eq(status: 'unavailable')
      expect(Crm::MetaAdsPostReading.count).to eq(0)

      responde
      expect(foto.ler).to include(status: 'ready')
    end

    it 'resposta fora do formato: não consegui ver agora' do
      allow(cliente).to receive(:create).and_return({ text: 'não é json' })

      expect(foto.ler).to eq(status: 'unavailable')
    end

    it 'a Meta fora do ar: não consegui ver agora, sem chamar a IA' do
      allow(cliente).to receive(:create)

      expect(foto(ler: -> { raise Crm::MetaAds::ComentariosIa::Rede::Indisponivel }).ler).to eq(status: 'unavailable')
      expect(cliente).not_to have_received(:create)
    end

    it 'IA desligada na instalação: não consegui ver agora, sem chamar' do
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)
      allow(cliente).to receive(:create)

      expect(foto.ler).to eq(status: 'unavailable')
      expect(cliente).not_to have_received(:create)
    end
  end

  it 'texto_para_ia: só da conta, da rede e do post certos' do
    create(:crm_meta_ads_post_reading, account: account, network: 'instagram', post_id: '1790', description: 'Bolo')

    expect(described_class.texto_para_ia(account, 'instagram', '1790')).to eq('Bolo')
    expect(described_class.texto_para_ia(create(:account), 'instagram', '1790')).to be_nil
    expect(described_class.texto_para_ia(account, 'facebook', '1790')).to be_nil
  end
end
