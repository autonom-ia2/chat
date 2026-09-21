require 'rails_helper'

# A pergunta ao Guia fora da requisição (#572), pela API que a tela usa.
#
# Existe porque, em 21/09/2026, uma pergunta que exigiu duas leituras morreu aos
# 15,2 segundos com erro 500: o `rack-timeout` de produção mata qualquer
# requisição aos 15, e a resposta do Guia saía de dentro dela.
RSpec.describe 'Guia da Plataforma — pergunta em segundo plano', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:rota) { "/api/v1/accounts/#{account.id}/autonomia/guide/chat" }

  before { allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true) }

  def perguntar(user, mensagem = 'quantas conversas abertas eu tenho?')
    post rota, params: { message: mensagem, route_context: 'home' },
               headers: user.create_new_auth_token, as: :json
    response.parsed_body['id']
  end

  def buscar(user, id)
    get "#{rota}/#{id}", headers: user.create_new_auth_token, as: :json
  end

  # O ponto inteiro: a requisição não espera o Guia. Ela abre o pedido e volta.
  it 'devolve na hora, sem esperar o Guia pensar', :aggregate_failures do
    expect(Autonomia::Guide::Chat).not_to receive(:new)

    perguntar(admin)

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body['status']).to eq('pending')
    expect(response.parsed_body['id']).to be_present
  end

  it 'põe o Guia para trabalhar com a pergunta, a pessoa e a conta certas' do
    expect do
      perguntar(admin, 'me fala sobre minhas conversas')
    end.to have_enqueued_job(Autonomia::Guide::ChatJob)
      .with(anything, hash_including('account_id' => account.id, 'user_id' => admin.id,
                                     'mensagem' => 'me fala sobre minhas conversas', 'tela' => 'home'))
  end

  # O histórico atravessa a fila: é serializado ao enfileirar e lido de volta no
  # job. Se ele se perder no caminho, o Guia esquece o assunto no meio da
  # conversa — calado, sem erro nenhum.
  it 'leva o histórico da conversa até o Guia, atravessando a fila' do
    recebido = nil
    allow(Autonomia::Guide::Chat).to receive(:new) do |**kwargs|
      recebido = kwargs[:history]
      instance_double(Autonomia::Guide::Chat, perform: Autonomia::Guide::Chat::Result.new(text: 'ok'))
    end
    historico = [{ role: 'user', content: 'quantos funis?' }, { role: 'assistant', content: 'São 3.' }]

    perform_enqueued_jobs(only: Autonomia::Guide::ChatJob) do
      post rota, params: { message: 'e quais são?', history: historico },
                 headers: admin.create_new_auth_token, as: :json
    end

    expect(recebido.map { |h| h[:content] }).to eq(['quantos funis?', 'São 3.'])
  end

  it 'mostra "pendente" enquanto o Guia ainda não terminou', :aggregate_failures do
    id = perguntar(admin)

    buscar(admin, id)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['status']).to eq('pending')
  end

  # Do começo ao fim: pergunta, job, resposta — com os mesmos campos que a tela
  # sempre leu.
  it 'entrega a resposta do Guia quando o job termina', :aggregate_failures do
    resultado = Autonomia::Guide::Chat::Result.new(text: 'Você tem 48 conversas abertas.', available: true,
                                                   grounded: true, confidence: 1.0, escalate: false)
    allow(Autonomia::Guide::Chat).to receive(:new)
      .and_return(instance_double(Autonomia::Guide::Chat, perform: resultado))

    id = nil
    # Só o job do Guia: criar usuário também enfileira o do avatar, que sai para
    # a internet — e esse não é o assunto aqui.
    perform_enqueued_jobs(only: Autonomia::Guide::ChatJob) { id = perguntar(admin) }
    buscar(admin, id)

    corpo = response.parsed_body
    expect(corpo['status']).to eq('done')
    expect(corpo['text']).to eq('Você tem 48 conversas abertas.')
    expect(corpo['available']).to be(true)
  end

  # A resposta foi montada com a permissão de quem perguntou. Outra pessoa da
  # mesma conta não lê — nem sabe que o pedido existe.
  it 'não entrega a resposta de uma pessoa a outra da mesma conta' do
    id = perguntar(admin)
    agente = create(:user, account: account, role: :agent)

    buscar(agente, id)

    expect(response).to have_http_status(:not_found)
  end

  it 'responde 404 para pedido que não existe' do
    buscar(admin, SecureRandom.uuid)

    expect(response).to have_http_status(:not_found)
  end
end
