require 'rails_helper'

# A conversa com o Guia guardada (#861), pela API que a tela usa. Antes ela
# vivia só na memória do navegador: recarregar a página apagava tudo.
RSpec.describe 'Guia da Plataforma — conversas guardadas', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/guide" }

  before { allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true) }

  def perguntar(user, mensagem, **extra)
    post "#{base}/chat", params: { message: mensagem, route_context: 'home' }.merge(extra),
                         headers: user.create_new_auth_token, as: :json
    response.body.present? ? response.parsed_body : {}
  end

  def responder_com(texto)
    resultado = Autonomia::Guide::Chat::Result.new(text: texto, available: true, grounded: true, confidence: 1.0,
                                                   escalate: false)
    allow(Autonomia::Guide::Chat).to receive(:new)
      .and_return(instance_double(Autonomia::Guide::Chat, perform: resultado))
  end

  def conversa_de(user, titulo = 'quantos funis?')
    conversa = Autonomia::Guide::Conversa.create!(account: account, user: user, titulo: titulo)
    Autonomia::Guide::Turno.abrir(conversa: conversa, pedido_id: SecureRandom.uuid, pergunta: titulo, tela: 'home')
    conversa
  end

  describe 'POST chat' do
    it 'abre uma conversa na primeira pergunta e guarda o turno', :aggregate_failures do
      corpo = perguntar(admin, 'quantos funis eu tenho?', anexos: [{ nome: 'apolice.pdf', tipo: 'documento' }])

      conversa = Autonomia::Guide::Conversa.find(corpo['conversa_id'])
      turno = conversa.turnos.first
      expect(conversa.user).to eq(admin)
      expect(conversa.titulo).to eq('quantos funis eu tenho?')
      expect(turno.pedido_id).to eq(corpo['id'])
      expect(turno.status).to eq('pending')
      expect(turno.anexos).to eq([{ 'nome' => 'apolice.pdf', 'tipo' => 'documento' }])
    end

    it 'continua a mesma conversa com conversa_id' do
      primeira = perguntar(admin, 'quantos funis?')
      perguntar(admin, 'e quais são?', conversa_id: primeira['conversa_id'])

      expect(Autonomia::Guide::Conversa.find(primeira['conversa_id']).turnos.size).to eq(2)
    end

    # O histórico que o Guia lê sai dos turnos guardados, não do navegador: o
    # que o cliente manda em `history` não vale quando a conversa já tem turno.
    it 'monta o histórico no servidor a partir dos turnos da conversa' do
      responder_com('São 3.')
      primeira = nil
      perform_enqueued_jobs(only: Autonomia::Guide::ChatJob) { primeira = perguntar(admin, 'quantos funis?') }

      recebido = nil
      allow(Autonomia::Guide::Chat).to receive(:new) do |**kwargs|
        recebido = kwargs[:history]
        instance_double(Autonomia::Guide::Chat, perform: Autonomia::Guide::Chat::Result.new(text: 'ok', available: true))
      end
      perform_enqueued_jobs(only: Autonomia::Guide::ChatJob) do
        perguntar(admin, 'e quais são?', conversa_id: primeira['conversa_id'],
                                         history: [{ role: 'user', content: 'texto inventado pelo cliente' }])
      end

      expect(recebido.map { |h| h[:content] }).to eq(['quantos funis?', 'São 3.'])
    end

    it 'responde 404 para conversa de outra pessoa, sem abrir pedido' do
      conversa = conversa_de(admin)

      expect do
        perguntar(agente, 'e agora?', conversa_id: conversa.id)
      end.not_to have_enqueued_job(Autonomia::Guide::ChatJob)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET conversas/atual' do
    it 'reabre a conversa mais recente com os turnos', :aggregate_failures do
      conversa_de(admin, 'antiga').update!(updated_at: 2.days.ago)
      recente = conversa_de(admin, 'recente')

      get "#{base}/conversas/atual", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['id']).to eq(recente.id)
      expect(response.parsed_body['turnos'].first).to include('pergunta' => 'recente', 'status' => 'pending')
    end

    it 'devolve vazio para quem nunca conversou' do
      conversa_de(admin)

      get "#{base}/conversas/atual", headers: agente.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq({})
    end
  end

  describe 'GET conversas' do
    it 'lista só as conversas da pessoa, com quantos turnos cada uma tem', :aggregate_failures do
      minha = conversa_de(agente, 'minha')
      conversa_de(admin, 'do admin')

      get "#{base}/conversas", headers: agente.create_new_auth_token, as: :json

      expect(response.parsed_body['conversas'].pluck('id')).to eq([minha.id])
      expect(response.parsed_body['conversas'].first['turnos']).to eq(1)
      expect(response.parsed_body).not_to have_key('retencao_dias')
    end
  end

  describe 'GET conversas/:id' do
    it 'abre a conversa da pessoa' do
      conversa = conversa_de(admin)

      get "#{base}/conversas/#{conversa.id}", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['turnos'].size).to eq(1)
    end

    # Outra pessoa da mesma conta não lê — nem sabe que a conversa existe.
    it 'responde 404 para conversa de outra pessoa da mesma conta' do
      conversa = conversa_de(admin)

      get "#{base}/conversas/#{conversa.id}", headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE conversas/:id' do
    it 'apaga a conversa e os turnos', :aggregate_failures do
      conversa = conversa_de(admin)

      delete "#{base}/conversas/#{conversa.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(Autonomia::Guide::Conversa.exists?(conversa.id)).to be(false)
      expect(Autonomia::Guide::Turno.where(conversation_id: conversa.id)).to be_empty
    end

    it 'não apaga a conversa de outra pessoa', :aggregate_failures do
      conversa = conversa_de(admin)

      delete "#{base}/conversas/#{conversa.id}", headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Autonomia::Guide::Conversa.exists?(conversa.id)).to be(true)
    end
  end

  describe 'sem permissão' do
    it 'quem não é da conta não lista nada' do
      de_fora = create(:user)

      get "#{base}/conversas", headers: de_fora.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'conta sem o Guia não tem conversa nenhuma' do
      allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(false)
      conversa_de(admin)

      get "#{base}/conversas/atual", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  # A ação sem desfazer, confirmada na tela: o desfecho fica no turno, e reabrir
  # a conversa não mostra os botões de novo.
  describe 'POST acoes/executar com pedido_id' do
    it 'guarda o desfecho da ação no turno', :aggregate_failures do
      conversa = conversa_de(admin)
      turno = conversa.turnos.first
      resultado = Autonomia::Guide::Acoes::Resultado.new(ok: true, mensagem: 'Pronto, feito.', registro: nil)
      allow(Autonomia::Guide::Acoes).to receive(:new).and_return(instance_double(Autonomia::Guide::Acoes, executar: resultado))

      post "#{base}/acoes/executar", params: { acao: 'DELETE inboxes/1', dados: {}, pedido_id: turno.pedido_id },
                                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(turno.reload.acao_estado).to eq('feita')
      expect(turno.acao_resultado).to eq('Pronto, feito.')
    end

    # Revisão da #861: a proposta guardada volta com os botões em outra aba ou
    # aparelho. Confirmar lá de novo não pode disparar a ação uma segunda vez.
    it 'não executa de novo uma ação que o turno já marca como feita', :aggregate_failures do
      turno = conversa_de(admin).turnos.first
      turno.update!(acao_estado: 'feita', acao_resultado: 'Pronto, feito.')
      acoes = instance_double(Autonomia::Guide::Acoes)
      allow(Autonomia::Guide::Acoes).to receive(:new).and_return(acoes)
      allow(acoes).to receive(:executar)

      post "#{base}/acoes/executar", params: { acao: 'POST campaigns', dados: {}, pedido_id: turno.pedido_id },
                                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to include('acao_estado' => 'feita', 'mensagem' => 'Pronto, feito.')
      expect(acoes).not_to have_received(:executar)
    end

    # Dois cliques ao mesmo tempo (duas abas): enquanto um executa, o outro não passa.
    it 'recusa a confirmação enquanto a mesma ação está sendo feita', :aggregate_failures do
      turno = conversa_de(admin).turnos.first
      acoes = instance_double(Autonomia::Guide::Acoes)
      allow(Autonomia::Guide::Acoes).to receive(:new).and_return(acoes)
      allow(acoes).to receive(:executar)
      Redis::LockManager.new.lock("autonomia:guide:acao:#{turno.id}", 30)

      post "#{base}/acoes/executar", params: { acao: 'POST campaigns', dados: {}, pedido_id: turno.pedido_id },
                                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(acoes).not_to have_received(:executar)
    ensure
      Redis::LockManager.new.unlock("autonomia:guide:acao:#{turno.id}")
    end
  end
end
