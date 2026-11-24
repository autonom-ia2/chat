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

  # #3158 (B8b) — o turno caiu depois de começar uma revisão: a tela recebe o cartão e não oferece "Tentar de novo",
  # que começaria outra, paga.
  it 'a falha leva a revisão que o turno começou', :aggregate_failures do
    conversa = Autonomia::Guide::Conversa.create!(account: conta, user: admin, titulo: 'revisão')
    turno = Autonomia::Guide::Turno.abrir(conversa: conversa, pedido_id: pedido, pergunta: 'revise', tela: 'home')
    revisao = Autonomia::Guide::Revisao.create!(account: conta, user: admin, turno: turno, status: 'na_fila', titulo: 'Revisão',
                                                pedido: 'Por quê', selecao: {}, ids: [1], limite: 300)
    allow(Autonomia::Guide::Chat).to receive(:new).and_raise(StandardError, 'caiu')

    rodar

    lido = Autonomia::Guide::Pedido.ler(pedido, account: conta, user: admin)
    expect(lido['status']).to eq('failed')
    expect(lido['revisao']).to eq({ 'id' => revisao.id, 'status' => 'na_fila' })
  end

  it 'marca a falha quando a pessoa ou a conta já não existem' do
    rodar(user_id: 0)

    expect(Autonomia::Guide::Pedido.ler(pedido, account: conta, user: admin)['status']).to eq('failed')
  end

  # Entrega 2 — a pessoa escreveu depois da última rodada do Guia: a mensagem não pode se perder.
  describe 'mensagem que chega depois da última rodada' do
    def escrever_durante(*textos, falha: false)
      novas = textos.map { SecureRandom.uuid }
      allow(Autonomia::Guide::Chat).to receive(:new) do
        novas.zip(textos).each do |nova, texto|
          Autonomia::Guide::Pedido.acrescentar(pedido, account: conta, user: admin, nova: nova, mensagem: texto)
        end
        raise StandardError, 'caiu' if falha

        instance_double(Autonomia::Guide::Chat, perform: resposta_do_guia('Criei as três.'))
      end
      novas
    end

    it 'vira a pergunta seguinte, que roda logo depois e a tela acompanha', :aggregate_failures do
      novas = escrever_durante('e mais uma', 'chama de Vendas')

      expect { rodar }.to have_enqueued_job(described_class)
        .with(novas.last, hash_including('mensagem' => "e mais uma\n\nchama de Vendas", 'user_id' => admin.id))

      lido = Autonomia::Guide::Pedido.ler(pedido, account: conta, user: admin)
      expect(lido).to include('status' => 'done', 'text' => 'Criei as três.', 'seguinte' => novas.last,
                              'tardias' => novas)
      expect(Autonomia::Guide::Pedido.ler(novas.first, account: conta, user: admin))
        .to include('status' => 'done', 'junto_de' => novas.last)
    end

    it 'segue adiante mesmo quando o turno falha' do
      novas = escrever_durante('tenta de novo', falha: true)

      expect { rodar }.to have_enqueued_job(described_class).with(novas.last, anything)
      expect(Autonomia::Guide::Pedido.ler(pedido, account: conta, user: admin))
        .to include('status' => 'failed', 'seguinte' => novas.last)
    end

    # Revisão do #3144: a mensagem que o Guia leu só conta como respondida se ele respondeu.
    def ler_durante(texto, resultado)
      nova = SecureRandom.uuid
      allow(Autonomia::Guide::Chat).to receive(:new) do
        Autonomia::Guide::Pedido.acrescentar(pedido, account: conta, user: admin, nova: nova, mensagem: texto)
        Autonomia::Guide::Pedido.ler_juntas(pedido)
        instance_double(Autonomia::Guide::Chat, perform: resultado)
      end
      nova
    end

    it 'lida e respondida fica junta deste pedido, sem pergunta seguinte', :aggregate_failures do
      nova = ler_durante('pare', resposta_do_guia('Parei.'))

      expect { rodar }.not_to have_enqueued_job(described_class)
      expect(Autonomia::Guide::Pedido.ler(pedido, account: conta, user: admin)).not_to have_key('seguinte')
      expect(Autonomia::Guide::Pedido.ler(nova, account: conta, user: admin)).to include('status' => 'done', 'junto_de' => pedido)
    end

    it 'lida sem resposta (retida) segue adiante como a pergunta seguinte' do
      retida = Autonomia::Guide::Chat::Result.new(text: nil, available: true, retido: true)
      nova = ler_durante('pare', retida)

      expect { rodar }.to have_enqueued_job(described_class).with(nova, hash_including('mensagem' => 'pare', 'arquivos' => []))
      expect(Autonomia::Guide::Pedido.ler(pedido, account: conta, user: admin)).to include('seguinte' => nova, 'tardias' => [nova])
    end

    it 'a resposta pronta não vira falha quando o fim do turno quebra', :aggregate_failures do
      conversa = Autonomia::Guide::Conversa.create!(account: conta, user: admin, titulo: 'teste')
      Autonomia::Guide::Turno.abrir(conversa: conversa, pedido_id: pedido, pergunta: 'oi', tela: 'home')
      allow(Autonomia::Guide::Chat).to receive(:new)
        .and_return(instance_double(Autonomia::Guide::Chat, perform: resposta_do_guia('Olá.')))
      allow(Autonomia::Guide::Pedido).to receive(:concluir).and_raise(Redis::CannotConnectError)

      rodar

      expect(Autonomia::Guide::Turno.find_by(pedido_id: pedido)).to have_attributes(status: 'done', resposta: 'Olá.')
    end

    # Conserto pós-deploy do #3144: sair como falha oferecia "Tentar de novo" para um turno que pode ter mexido na conta.
    it 'o fim do turno deu erro, mas a resposta existe: o pedido sai com ela, não como falha' do
      allow(Autonomia::Guide::Chat).to receive(:new)
        .and_return(instance_double(Autonomia::Guide::Chat, perform: resposta_do_guia('Criei.')))
      tentativas = 0
      allow(Autonomia::Guide::Pedido).to receive(:concluir).and_wrap_original do |original, *args|
        tentativas += 1
        raise Redis::CannotConnectError if tentativas == 1

        original.call(*args)
      end

      rodar

      expect(Autonomia::Guide::Pedido.ler(pedido, account: conta, user: admin)).to include('status' => 'done', 'text' => 'Criei.')
    end

    # Revisão do conserto: o `falhou` encerrava de novo e achava a fila vazia — o pedido saía sem `seguinte`.
    it 'o pedido que não gravou de primeira ainda leva a pergunta seguinte que já está rodando', :aggregate_failures do
      nova = SecureRandom.uuid
      allow(Autonomia::Guide::Chat).to receive(:new) do
        Autonomia::Guide::Pedido.acrescentar(pedido, account: conta, user: admin, nova: nova, mensagem: 'e mais uma')
        instance_double(Autonomia::Guide::Chat, perform: resposta_do_guia('Criei.'))
      end
      tentativas = 0
      allow(Autonomia::Guide::Pedido).to receive(:concluir).and_wrap_original do |original, id, resultado|
        tentativas += 1 if id == pedido
        raise Redis::CannotConnectError if id == pedido && tentativas == 1

        original.call(id, resultado)
      end

      expect { rodar }.to have_enqueued_job(described_class).with(nova, anything).exactly(:once)
      expect(Autonomia::Guide::Pedido.ler(pedido, account: conta, user: admin))
        .to include('status' => 'done', 'seguinte' => nova, 'tardias' => [nova])
    end

    it 'trava ocupada no fim do turno: as mensagens da fila seguem adiante mesmo assim' do
      nova = SecureRandom.uuid
      Autonomia::Guide::Pedido.acrescentar(pedido, account: conta, user: admin, nova: nova, mensagem: 'e mais uma')
      allow(Autonomia::Guide::Chat).to receive(:new)
        .and_return(instance_double(Autonomia::Guide::Chat, perform: resposta_do_guia('ok')))
      allow(Autonomia::Guide::Pedido).to receive(:com_trava).and_raise(Autonomia::Guide::Pedido::TravaOcupada)

      expect { rodar }.to have_enqueued_job(described_class).with(nova, anything)
    end

    it 'sem mensagem nova, o pedido termina sem pergunta seguinte' do
      allow(Autonomia::Guide::Chat).to receive(:new)
        .and_return(instance_double(Autonomia::Guide::Chat, perform: resposta_do_guia('ok')))

      expect { rodar }.not_to have_enqueued_job(described_class)
      expect(Autonomia::Guide::Pedido.ler(pedido, account: conta, user: admin)).not_to have_key('seguinte')
    end
  end
end
