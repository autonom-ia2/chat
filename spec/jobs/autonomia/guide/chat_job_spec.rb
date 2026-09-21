require 'rails_helper'

# O Guia respondendo fora da requisição (#572).
RSpec.describe Autonomia::Guide::ChatJob do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:pedido) { Autonomia::Guide::Pedido.abrir(account: conta, user: admin) }

  def resposta_do_guia(texto)
    Autonomia::Guide::Chat::Result.new(text: texto, available: true, grounded: true, confidence: 1.0,
                                       escalate: false, navigation: nil, acao: nil)
  end

  def pergunta(mensagem: 'quantas conversas eu tenho?', locale: 'pt_BR', user_id: admin.id)
    { 'account_id' => conta.id, 'user_id' => user_id, 'mensagem' => mensagem,
      'historico' => [], 'tela' => 'home', 'locale' => locale }
  end

  def rodar(**)
    described_class.perform_now(pedido, pergunta(**))
  end

  it 'responde com a mesma pessoa e a mesma conta que perguntaram', :aggregate_failures do
    recebido = {}
    allow(Autonomia::Guide::Chat).to receive(:new) do |**kwargs|
      recebido = kwargs
      instance_double(Autonomia::Guide::Chat, perform: resposta_do_guia('Você tem 48.'))
    end

    rodar

    expect(recebido[:account]).to eq(conta)
    expect(recebido[:user]).to eq(admin)
    expect(Autonomia::Guide::Pedido.ler(pedido, account: conta, user: admin)['text']).to eq('Você tem 48.')
  end

  # A frase do botão de confirmar e o aviso de que apagar não tem volta saem do
  # I18n. O job não herda o idioma de ninguém: sem isto, quem usa em português
  # veria o cartão de confirmação em inglês.
  it 'responde no idioma de quem perguntou' do
    idioma = nil
    allow(Autonomia::Guide::Chat).to receive(:new) do
      idioma = I18n.locale
      instance_double(Autonomia::Guide::Chat, perform: resposta_do_guia('ok'))
    end

    rodar(locale: 'pt_BR')

    expect(idioma.to_s).to eq('pt_BR')
  end

  # A tela busca até o pedido sair de "pendente". Se o job morrer sem marcar,
  # ela espera os três minutos inteiros para então dizer que falhou.
  it 'marca a falha quando o Guia estoura, em vez de deixar a tela esperando' do
    allow(Autonomia::Guide::Chat).to receive(:new).and_raise(StandardError, 'caiu')

    rodar

    expect(Autonomia::Guide::Pedido.ler(pedido, account: conta, user: admin)['status']).to eq('failed')
  end

  it 'marca a falha quando a pessoa ou a conta já não existem' do
    rodar(user_id: 0)

    expect(Autonomia::Guide::Pedido.ler(pedido, account: conta, user: admin)['status']).to eq('failed')
  end
end
