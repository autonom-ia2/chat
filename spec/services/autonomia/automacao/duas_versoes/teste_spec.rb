require 'rails_helper'

# #3099: o teste das duas versões de um passo da automação — os números desde `teste_desde`, quando fecha, o estado, a
# escolha automática (a régua da campanha) e a escolha de uma vez só. O mínimo por versão cai para 5 só aqui, para o
# spec não precisar de 200 envios; a régua da vencedora (10 respostas somadas, 15% de diferença) é a de verdade.
RSpec.describe Autonomia::Automacao::DuasVersoes::Teste, :automacao_motor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:automacao) { create(:autonomia_automacao, account: account) }
  let(:regra) { { 'criterio' => 'respostas', 'divisao' => 50, 'espera' => 4 } }
  let(:passo) { mensagem_passo('p1', 'Oi').merge('versoes' => regra.merge('texto' => ['Olá'], 'modelo' => nil)) }
  let(:linha) do
    Autonomia::Automacao::VersaoVencedora.create!(account: account, automacao: automacao, passo: 'p1', teste_desde: 1.day.ago)
  end

  before { stub_const('Autonomia::Automacao::DuasVersoes::MINIMO_POR_VERSAO', 5) }

  # `quantos` envios da versão, cada um para um contato novo; os `responderam` primeiros escrevem 1 hora depois.
  def envios(versao, quantos, quando:, responderam: 0)
    Array.new(quantos) do |indice|
      contato = create(:contact, account: account)
      Autonomia::Automacao::VersaoEnvio.create!(account: account, automacao: automacao, passo: 'p1', alvo_type: 'Contact',
                                                alvo_id: contato.id, contact: contato, versao: versao, created_at: quando)
      responder(contato, quando + 1.hour) if indice < responderam
    end
  end

  def responder(contato, quando)
    conversa = create(:conversation, account: account, contact: contato)
    create(:message, conversation: conversa, account: account, inbox: conversa.inbox, sender: contato, message_type: :incoming,
                     content: 'oi', created_at: quando)
  end

  def teste(passo_da_regra = passo) = described_class.new(linha, passo_da_regra)

  describe 'os números' do
    it 'contam só desde o começo do teste e dizem quanto falta', :aggregate_failures do
      envios(1, 3, quando: 2.days.ago)
      envios(1, 5, quando: 10.hours.ago)
      envios(2, 3, quando: 10.hours.ago)

      numeros = Autonomia::Automacao::DuasVersoes::Numeros.new(linha)
      expect(numeros.receberam).to eq(1 => 5, 2 => 3)
      expect(numeros.faltam).to eq(2)
      expect(numeros.fechou_em).to be_nil
      expect(teste.estado).to eq('testando')
      expect(teste.escolhe_em).to be_nil
    end

    it 'resposta conta só depois do envio e até 72 horas', :aggregate_failures do
      linha.update!(teste_desde: 5.days.ago)
      envio = 4.days.ago
      antes, depois, a_tempo = Array.new(3) { create(:contact, account: account) }
      [antes, depois, a_tempo].each do |contato|
        Autonomia::Automacao::VersaoEnvio.create!(account: account, automacao: automacao, passo: 'p1', alvo_type: 'Contact',
                                                  alvo_id: contato.id, contact: contato, versao: 1, created_at: envio)
      end
      responder(antes, envio - 1.hour)
      responder(depois, envio + 73.hours)
      responder(a_tempo, envio + 2.hours)

      expect(Autonomia::Automacao::DuasVersoes::Numeros.new(linha).por_versao.first).to include(receberam: 3, responderam: 1)
    end

    it 'o teste fecha quando a versão mais atrasada chega ao mínimo, e a hora de escolher é o fechamento + a espera' do
      envios(1, 5, quando: 10.hours.ago)
      envios(2, 5, quando: 8.hours.ago)

      expect(teste.escolhe_em).to be_within(1.second).of(8.hours.ago + 4.hours)
    end
  end

  describe '#decidir!' do
    it 'na hora, fica a versão com mais respostas', :aggregate_failures do
      envios(1, 20, quando: 10.hours.ago, responderam: 2)
      envios(2, 20, quando: 10.hours.ago, responderam: 12)

      expect(teste.decidir!).to be(true)
      expect(linha.reload).to have_attributes(vencedora: 2, escolhida_por: 'sistema')
      expect(teste.estado).to eq('escolhida')
    end

    it 'poucas respostas é empate: fica a versão 1' do
      envios(1, 20, quando: 10.hours.ago, responderam: 1)
      envios(2, 20, quando: 10.hours.ago, responderam: 3)

      teste.decidir!
      expect(linha.reload).to have_attributes(vencedora: 1, escolhida_por: 'empate')
    end

    it 'antes da espera não escolhe' do
      envios(1, 20, quando: 1.hour.ago, responderam: 2)
      envios(2, 20, quando: 1.hour.ago, responderam: 12)

      expect(teste.decidir!).to be(false)
      expect(linha.reload.vencedora).to be_nil
    end

    it 'no "eu escolho", passa a esperar a pessoa e não escolhe sozinho', :aggregate_failures do
      envios(1, 20, quando: 10.hours.ago, responderam: 2)
      envios(2, 20, quando: 10.hours.ago, responderam: 12)
      eu_escolho = passo.deep_merge('versoes' => { 'criterio' => 'eu_escolho' })

      expect(teste(eu_escolho).decidir!).to be(false)
      expect(teste(eu_escolho).estado).to eq('esperando_voce')
      expect(linha.reload.vencedora).to be_nil
    end
  end

  describe '#escolher!' do
    it 'escolhe uma vez só' do
      expect(teste.escolher!(2, por: 'voce', user: admin)).to be(true)
      expect(teste.escolher!(1, por: 'voce', user: admin)).to be(false)
      expect(linha.reload).to have_attributes(vencedora: 2, escolhida_por: 'voce', escolhida_por_user_id: admin.id)
    end
  end

  describe '#payload' do
    it 'traz o estado, a regra e os números de cada versão', :aggregate_failures do
      envios(1, 2, quando: 1.hour.ago)
      payload = teste.payload(user: admin, account_user: account.account_users.find_by(user: admin))

      expect(payload).to include(passo: 'p1', estado: 'testando', criterio: 'respostas', espera: 4, faltam: 5, vencedora: nil)
      expect(payload[:versoes].pluck(:numero, :receberam)).to eq([[1, 2], [2, 0]])
    end
  end
end
