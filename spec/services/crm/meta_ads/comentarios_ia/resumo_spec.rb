require 'rails_helper'

# O bloco "O que tem nos comentários" (#2454): antes do clique do dono, só o que o código conta. Nenhuma IA.
RSpec.describe Crm::MetaAds::ComentariosIa::Resumo do
  let(:account) { create(:account) }
  let(:alvo) { { 'kind' => 'post', 'perfil' => 'ig-1', 'post_id' => '1790' } }
  let(:fonte) { instance_double(Crm::MetaAds::ComentariosIa::Fonte) }
  let(:resumo) { described_class.new(account: account, alvo: alvo, fonte: fonte) }
  let(:linhas) do
    [linha('1', dias: 1), linha('2', dias: 3), linha('3', dias: 6), linha('4', dias: 9), linha('5', dias: 30)]
  end

  def linha(id, dias:)
    { id: id, network: 'instagram', author: 'pessoa', text: 'Quanto custa?', momento: dias.days.ago }
  end

  before do
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: linhas, escondidas: [] })
    allow(Crm::MetaAds::ComentariosIa::Classificador).to receive(:new)
    allow(Crm::Ai::ResponsesClient).to receive(:new)
  end

  it 'conta quantos esperam resposta e quantos ainda cabem no privado (até 7 dias)' do
    expect(resumo.call).to eq(status: 'ready', waiting: 5, private_window: 3)
  end

  describe 'as respostas de cliente dentro dos comentários (#2454)' do
    before do
      respostas = [linha('1a', dias: 1).merge(parent_id: '1'), linha('4a', dias: 9).merge(parent_id: '4')]
      allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: linhas, escondidas: [], respostas_que_esperam: respostas })
    end

    it 'com a flag da conversa: o fio conta, nos que esperam e nos que cabem no privado' do
      account.enable_features!(Crm::MetaAds::ComentariosIa::Foto::FLAG)

      expect(resumo.call).to eq(status: 'ready', waiting: 7, private_window: 4)
    end

    it 'sem a flag: como antes, só os de primeiro nível' do
      expect(resumo.call).to eq(status: 'ready', waiting: 5, private_window: 3)
    end
  end

  it 'sem nenhuma IA: nem o Classificador, nem o cliente, nem uso gravado' do
    resumo.call

    expect(Crm::MetaAds::ComentariosIa::Classificador).not_to have_received(:new)
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    expect(Crm::AiUsageEvent.count).to eq(0)
  end

  it 'sem data do comentário: espera, mas não cabe no privado' do
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', dias: 1).merge(momento: nil)], escondidas: [] })

    expect(resumo.call).to eq(status: 'ready', waiting: 1, private_window: 0)
  end

  it 'ninguém esperando: zero e zero' do
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [], escondidas: [] })

    expect(resumo.call).to eq(status: 'ready', waiting: 0, private_window: 0)
  end

  it 'leitura que não ficou pronta: devolve o status, sem contar' do
    allow(fonte).to receive(:ler).and_return({ status: 'needs_permission', linhas: [], escondidas: [] })

    expect(resumo.call).to eq(status: 'needs_permission')
  end

  it 'perfil ou conexão que não existem mais: not_found' do
    expect(described_class.new(account: account, alvo: alvo).call).to eq(status: 'not_found')
  end
end
