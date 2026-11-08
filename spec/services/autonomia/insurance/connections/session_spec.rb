require 'rails_helper'

# A sessão mora na CONEXÃO para ser compartilhada — não porque o portal proíba ter duas.
#
# (Correção de 11/09/2026: aqui se lia "o portal aceita UMA sessão viva por login: abrir outra
# invalida a anterior". Medido e falso — ver o cabeçalho de `connections/session.rb`.) Estes testes
# travam o contrato que faz várias cotações da mesma corretora conviverem com UM login, e que faz o
# healthcheck e o polling REUSAREM esse login em vez de abrir um por passada.
#
# (Correção de 11/09/2026, segunda: a frase aqui era "e que impede o healthcheck da tela de Conexões
# de encerrar a sessão de uma cotação em andamento". Ela sobrevivia à correção de cima porque estava
# em paráfrase: sob a medição, o login do healthcheck não encerra sessão nenhuma — o portal
# compartilha. O que o reuso evita é CUSTO, e a contagem de logins destes exemplos é exatamente
# isso.)
RSpec.describe Autonomia::Insurance::Connections::Session do
  let(:account) { create(:account) }

  before { enable_test_encryption! }

  # REGRESSÃO REAL, 05/09/2026: toda chamada morrendo em `GET /cfg/corretora -> 403`, e a tela
  # dizendo "credencial recusada" com a credencial perfeitamente válida. `renew!` já existia e
  # ninguém o chamava.
  #
  # (Correção de 11/09/2026: este parágrafo atribuía a regressão a "o corretor abriu o portal do
  # AGGER pelo navegador; o AGGER aceita uma sessão por login e derrubou a nossa" — a mesma frase
  # que o cabeçalho deste arquivo declara falsa três linhas acima. A CAUSA PROVADA do 403 é outra e
  # já está corrigida: o handler do adapter redigia o corpo da resposta, o `aggregatorToken` chegava
  # como a palavra `<REDACTED>` e era ISSO que viajava em `Authorization` — medido invocando o
  # Lambda de produção, `autonomia-adapters` c9b88bd.)
  #
  # O MOTIVO HONESTO de `with_fresh_session` não depende daquela causa, e é o que estes exemplos
  # travam: `session_live?` só conhece o PRAZO QUE NÓS GRAVAMOS, e prazo gravado não é prova. Se a
  # sessão acabar antes dele, a linha fica com uma sessão que PARECE viva e toda chamada morre em
  # 403 até o prazo vencer — com ou sem terceiro na conta.
  describe '#with_fresh_session' do
    let(:renew_account) { create(:account) }
    let(:renew_connection) do
      record = Autonomia::Insurance::Connection.create!(account: renew_account, username: 'c@x.com',
                                                        password: 'segredo')
      record.store_session!({ 'multicalculoToken' => 'morta' }, expires_at: 3.hours.from_now)
      record
    end
    let(:renew_connector) do
      instance_double(Autonomia::Insurance::Connector::Mock,
                      open_session: { 'platform' => 'agger', 'data' => { 'token' => 'nova' },
                                      'expires_at' => 3.hours.from_now.utc.iso8601 })
    end

    it 'opens another session when the portal refuses the stored one' do
      # Arrange — o portal recusa a sessão guardada; o login seguinte funciona
      tentativas = 0

      # Act
      resultado = described_class.new(renew_connection, connector: renew_connector).with_fresh_session do |session|
        tentativas += 1
        raise Autonomia::Insurance::Connector::Error.new(:auth_required, 'GET /cfg/corretora -> 403') if tentativas == 1

        session
      end

      # Assert — a segunda passada recebe a sessão NOVA, não a que o portal recusou.
      # O que fica guardado é o `data` do payload, não o envelope.
      expect(tentativas).to eq(2)
      expect(resultado.to_h).to eq({ 'token' => 'nova' })
    end

    it 'gives up after one renewal, because insisting only piles up logins' do
      # Arrange — credencial de fato inválida: renovar não resolve
      tentativas = 0

      # Act / Assert
      expect do
        described_class.new(renew_connection, connector: renew_connector).with_fresh_session do
          tentativas += 1
          raise Autonomia::Insurance::Connector::Error.new(:auth_required, 'recusado')
        end
      end.to raise_error(Autonomia::Insurance::Connector::Error)
      expect(tentativas).to eq(2)
    end

    # Achado 5 da auditoria (05/11/2026): com a sessão gravada JÁ VENCIDA, o próprio login era recusado
    # e a renovação fazia outro login igual. Um login por chamada.
    it 'does not log in twice when the login itself is refused' do
      # Arrange — sessão gravada e vencida; o portal recusa a credencial
      vencida = Autonomia::Insurance::Connection.create!(account: renew_account, username: 'v@x.com', password: 'segredo')
      vencida.store_session!({ 'multicalculoToken' => 'velha' }, expires_at: 1.hour.ago)
      recusa = counting_connector
      def recusa.open_session(**)
        @logins += 1
        raise Autonomia::Insurance::Connector::Error.new(:auth_required, 'credential rejected')
      end
      rodou = false

      # Act / Assert
      expect do
        described_class.new(vencida, connector: recusa).with_fresh_session { rodou = true }
      end.to raise_error(an_object_having_attributes(kind: :auth_required))
      expect(recusa.logins).to eq(1)
      expect(rodou).to be(false)
    end

    it 'does not renew a session that was just opened: the portal would hand back the same one' do
      # Arrange — nada guardado; abre, e o portal recusa a sessão recém-aberta
      nova = Autonomia::Insurance::Connection.create!(account: renew_account, username: 'n@x.com', password: 'segredo')
      connector = counting_connector
      tentativas = 0

      # Act / Assert
      expect do
        described_class.new(nova, connector: connector).with_fresh_session do
          tentativas += 1
          raise Autonomia::Insurance::Connector::Error.new(:auth_required, '403')
        end
      end.to raise_error(Autonomia::Insurance::Connector::Error)
      expect(tentativas).to eq(1)
      expect(connector.logins).to eq(1)
    end

    it 'does not renew for an error that has nothing to do with the session' do
      # Arrange — portal fora do ar não vira login novo
      tentativas = 0

      # Act / Assert
      expect do
        described_class.new(renew_connection, connector: renew_connector).with_fresh_session do
          tentativas += 1
          raise Autonomia::Insurance::Connector::Error.new(:unavailable, 'portal fora')
        end
      end.to raise_error(Autonomia::Insurance::Connector::Error)
      expect(tentativas).to eq(1)
    end
  end

  # A CONSULTA DE PLACA RODA NO TURNO (entrega 2), e o turno não espera login: aqui só serve a
  # sessão que já está viva. Sem ela o bloco não roda; recusada pelo portal, o erro sobe sem
  # renovação — quem abre e renova é o healthcheck e o job, fora do turno.
  describe '#with_live_session' do
    it 'hands over the live session without touching the portal' do
      record = connection
      record.store_session!({ 'multicalculoToken' => 'viva' }, expires_at: 3.hours.from_now)
      connector = counting_connector

      resultado = described_class.new(record, connector: connector).with_live_session { |s| s['multicalculoToken'] }

      expect(resultado).to eq('viva')
      expect(connector.logins).to eq(0)
    end

    it 'does not open a session when none is alive: the block does not run' do
      record = connection
      connector = counting_connector
      rodou = false

      resultado = described_class.new(record, connector: connector).with_live_session { rodou = true }

      expect(resultado).to be_nil
      expect(rodou).to be(false)
      expect(connector.logins).to eq(0)
    end

    it 'does not renew when the portal refuses the stored session: the error goes up' do
      record = connection
      record.store_session!({ 'multicalculoToken' => 'morta' }, expires_at: 3.hours.from_now)
      connector = counting_connector

      expect do
        described_class.new(record, connector: connector).with_live_session do
          raise Autonomia::Insurance::Connector::Error.new(:auth_required, '403')
        end
      end.to raise_error(Autonomia::Insurance::Connector::Error)
      expect(connector.logins).to eq(0)
    end
  end

  def connection
    Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
  end

  # Connector que CONTA quantas vezes abriu sessão. É o número que importa, e o que ele mede é CUSTO:
  # cada login a mais é uma chamada de até `Http::READ_TIMEOUT` segundos ao portal para receber de
  # volta a sessão que já tínhamos.
  #
  # (Correção de 11/09/2026: aqui se lia "cada login a mais é uma sessão a menos para quem estava
  # usando a anterior". Medido e falso — logins da mesma conta compartilham a sessão. Esta paráfrase
  # atravessou a guarda de palavra da rodada 4 sem ser acusada, e é por isso que a guarda saiu.)
  def counting_connector(expires_in: 3.hours)
    Class.new(Autonomia::Insurance::Connector::Client) do
      attr_reader :logins

      define_method(:initialize) do
        super()
        @logins = 0
        @expires_in = expires_in
      end

      define_method(:open_session) do |**|
        @logins += 1
        { 'platform' => 'agger', 'data' => { 'multicalculoToken' => "token-#{@logins}" },
          'expires_at' => @expires_in.from_now.utc.iso8601, 'account_label' => 'CORRETORA X' }
      end
    end.new
  end

  it 'opens the session once and hands the same one to every caller' do
    # Arrange
    record = connection
    connector = counting_connector

    # Act — três consumidores diferentes pedindo a sessão da mesma conexão
    first = described_class.new(record, connector: connector).resolve!
    second = described_class.new(record.reload, connector: connector).resolve!
    third = described_class.new(record.reload, connector: connector).resolve!

    # Assert
    expect(connector.logins).to eq(1)
    expect(first).to eq(second).and eq(third)
    expect(record.reload.session_expires_at).to be_present
    expect(record.external_account_label).to eq('CORRETORA X')
  end

  it 'stores the session encrypted, never in plain text' do
    # Arrange
    record = connection

    # Act
    described_class.new(record, connector: counting_connector).resolve!

    # Assert — o valor cru na coluna não pode conter o token
    raw = Autonomia::Insurance::Connection.connection.select_value(
      "SELECT session_payload FROM autonomia_insurance_connections WHERE id = #{record.id}"
    )
    expect(record.reload.session['multicalculoToken']).to eq('token-1')
    expect(raw).not_to include('token-1')
  end

  it 'opens a single session when two quotes start at the same time' do
    # Arrange — duas execuções concorrentes sobre a mesma linha
    record = connection
    connector = counting_connector
    other = Autonomia::Insurance::Connection.find(record.id)

    # Act — o recheck DENTRO do lock é o que evita o segundo login
    described_class.new(record, connector: connector).resolve!
    described_class.new(other, connector: connector).resolve!

    # Assert
    expect(connector.logins).to eq(1)
  end

  it 'opens a new session when the stored one is about to expire' do
    # Arrange — dentro da margem: renovar cedo evita a sessão morrer no meio de um polling
    record = connection
    connector = counting_connector(expires_in: 1.minute)

    # Act
    described_class.new(record, connector: connector).resolve!
    described_class.new(record.reload, connector: connector).resolve!

    # Assert
    expect(connector.logins).to eq(2)
  end

  it 'never reuses a session the portal did not put a deadline on' do
    # Arrange — sem prazo não dá para saber se ainda vale; um login a mais é melhor do que uma
    # cotação que morre no meio
    record = connection
    connector = Class.new(Autonomia::Insurance::Connector::Client) do
      attr_reader :logins

      def initialize
        super
        @logins = 0
      end

      def open_session(**)
        @logins += 1
        { 'platform' => 'agger', 'data' => { 'token' => 'x' } }
      end
    end.new

    # Act
    described_class.new(record, connector: connector).resolve!
    described_class.new(record.reload, connector: connector).resolve!

    # Assert
    expect(connector.logins).to eq(2)
  end

  it 'renews by forgetting the stored session first' do
    # Arrange
    record = connection
    connector = counting_connector

    # Act — é o caminho de "o portal recusou o que guardamos"
    described_class.new(record, connector: connector).resolve!
    renewed = described_class.new(record.reload, connector: connector).renew!

    # Assert
    expect(connector.logins).to eq(2)
    expect(renewed['multicalculoToken']).to eq('token-2')
    expect(record.reload.session['multicalculoToken']).to eq('token-2')
  end

  # Achado 12: entre a recusa e a renovação, outro processo pode ter aberto uma sessão nova. Só a
  # sessão RECUSADA é esquecida; a nova é reusada, sem login a mais.
  it 'keeps the session another process opened meanwhile, instead of forgetting it' do
    # Arrange — a recusada era token-1; outro processo já gravou token-2
    record = connection
    connector = counting_connector
    recusada = described_class.new(record, connector: connector).resolve!
    Autonomia::Insurance::Connection.find(record.id)
                                    .store_session!({ 'multicalculoToken' => 'do-outro' }, expires_at: 3.hours.from_now)

    # Act
    renovada = described_class.new(record, connector: connector).renew!(recusada)

    # Assert
    expect(renovada['multicalculoToken']).to eq('do-outro')
    expect(connector.logins).to eq(1)
  end

  # Achado 11: o login (até 60 s) não segura mais trava de linha. Quem chega enquanto outro processo
  # abre a sessão espera fora do banco e usa a sessão dele.
  describe 'a trava do login' do
    let(:chave) { "autonomia:insurance:connection:#{record.id}:login" }
    let(:record) { connection }

    after do
      Redis::LockManager.new.unlock(chave)
      Redis::Alfred.delete("autonomia:insurance:connection:#{record.id}:login_recusado")
    end

    it 'waits for the session another process is opening and does not log in again' do
      # Arrange — outro processo segura a trava e grava a sessão enquanto este espera
      Redis::LockManager.new.lock(chave, 95)
      connector = counting_connector
      sessao = described_class.new(record, connector: connector)
      allow(sessao).to receive(:sleep) do
        Autonomia::Insurance::Connection.find(record.id)
                                        .store_session!({ 'multicalculoToken' => 'do-outro' }, expires_at: 3.hours.from_now)
      end

      # Act
      resultado = sessao.resolve!

      # Assert
      expect(resultado['multicalculoToken']).to eq('do-outro')
      expect(connector.logins).to eq(0)
    end

    it 'opens the session itself once the other process lets go without one' do
      # Arrange — o outro processo solta a trava sem gravar sessão (o login dele falhou)
      Redis::LockManager.new.lock(chave, 95)
      connector = counting_connector
      sessao = described_class.new(record, connector: connector)
      allow(sessao).to receive(:sleep) { Redis::LockManager.new.unlock(chave) }

      # Act
      resultado = sessao.resolve!

      # Assert
      expect(resultado['multicalculoToken']).to eq('token-1')
      expect(connector.logins).to eq(1)
    end

    it 'gives up with a timeout when the other process never finishes' do
      # Arrange — o outro processo continua segurando a trava (a do MockRedis vence com o `travel`,
      # então ela é pega de novo a cada olhada)
      Redis::LockManager.new.lock(chave, 95)
      sessao = described_class.new(record, connector: counting_connector)
      allow(sessao).to receive(:sleep) do
        travel(30.seconds)
        Redis::LockManager.new.lock(chave, 95)
      end

      # Act / Assert
      expect { sessao.resolve! }.to raise_error(an_object_having_attributes(kind: :timeout))
    end

    it 'inherits the refusal of the login it waited for, instead of trying its own' do
      # Arrange — o outro processo tenta, o portal recusa ("Sessões lotadas"), e ele solta a trava
      Redis::LockManager.new.lock(chave, 95)
      connector = counting_connector
      sessao = described_class.new(record, connector: connector)
      outro = described_class.new(Autonomia::Insurance::Connection.find(record.id), connector: counting_connector)
      allow(sessao).to receive(:sleep) do
        Redis::LockManager.new.unlock(chave)
        lotadas = Autonomia::Insurance::Connector::Error.new(:unavailable, 'sessions full',
                                                             { 'failure' => { 'cause' => 'sessions_full' } })
        outro.send(:registrar_recusa!, lotadas)
        Redis::LockManager.new.lock(chave, 95)
      end

      # Act / Assert
      expect { sessao.resolve! }.to raise_error(an_object_having_attributes(kind: :unavailable))
      expect(connector.logins).to eq(0)
    end

    it 'inherits a refusal from the last seconds even when the lock is already free' do
      # Arrange — o outro processo foi recusado e já soltou a trava; este chega logo depois
      outro = described_class.new(Autonomia::Insurance::Connection.find(record.id), connector: counting_connector)
      outro.send(:registrar_recusa!, Autonomia::Insurance::Connector::Error.new(:unavailable, 'sessions full'))
      connector = counting_connector

      # Act / Assert — sem login novo
      expect { described_class.new(record, connector: connector).resolve! }
        .to raise_error(an_object_having_attributes(kind: :unavailable))
      expect(connector.logins).to eq(0)
    end

    it 'tests a new password instead of inheriting the refusal of the old one' do
      # Arrange — recusa com a senha antiga; o corretor salva a senha nova logo em seguida
      outro = described_class.new(Autonomia::Insurance::Connection.find(record.id), connector: counting_connector)
      outro.send(:registrar_recusa!, Autonomia::Insurance::Connector::Error.new(:auth_required, 'credential rejected'))
      record.update!(password: 'senha-nova')
      connector = counting_connector

      # Act
      resultado = described_class.new(record, connector: connector).resolve!

      # Assert
      expect(resultado['multicalculoToken']).to eq('token-1')
      expect(connector.logins).to eq(1)
    end

    it 'tries again once the refusal is old' do
      # Arrange — recusa gravada há mais de `RECUSA_VISIVEL` (o MockRedis vence a chave com o `travel`)
      outro = described_class.new(Autonomia::Insurance::Connection.find(record.id), connector: counting_connector)
      outro.send(:registrar_recusa!, Autonomia::Insurance::Connector::Error.new(:unavailable, 'velha'))
      travel(described_class::RECUSA_VISIVEL + 1.second)
      connector = counting_connector

      # Act
      resultado = described_class.new(record, connector: connector).resolve!

      # Assert
      expect(resultado['multicalculoToken']).to eq('token-1')
      expect(connector.logins).to eq(1)
    end

    it 'does not extend the refusal when it only relays it' do
      # Arrange
      outro = described_class.new(Autonomia::Insurance::Connection.find(record.id), connector: counting_connector)
      outro.send(:registrar_recusa!, Autonomia::Insurance::Connector::Error.new(:unavailable, 'sessions full'))
      chave_recusa = "autonomia:insurance:connection:#{record.id}:login_recusado"
      gravada = Redis::Alfred.get(chave_recusa)

      # Act
      expect { described_class.new(record, connector: counting_connector).resolve! }.to raise_error(Autonomia::Insurance::Connector::Error)

      # Assert — a recusa continua a mesma, com o prazo de antes
      expect(Redis::Alfred.get(chave_recusa)).to eq(gravada)
    end

    it 'waits only as long as the caller allows (the web request passes a short wait)' do
      # Arrange
      Redis::LockManager.new.lock(chave, 95)
      sessao = described_class.new(record, connector: counting_connector, espera: 10.seconds)
      allow(sessao).to receive(:sleep) { travel(6.seconds) }

      # Act / Assert — dois cochilos de 6 s passam dos 10 s
      expect { sessao.resolve! }.to raise_error(an_object_having_attributes(kind: :timeout, causa: :espera_do_login))
    end

    it 'releases the lock even when the login fails' do
      # Arrange
      recusa = counting_connector
      def recusa.open_session(**) = raise(Autonomia::Insurance::Connector::Error.new(:unavailable, 'portal fora'))

      # Act
      expect { described_class.new(record, connector: recusa).resolve! }.to raise_error(Autonomia::Insurance::Connector::Error)

      # Assert
      expect(Redis::LockManager.new.lock(chave, 1)).to be(true)
    end
  end

  it 'refuses to open a session without credentials' do
    # Arrange
    empty = Autonomia::Insurance::Connection.create!(account: account)

    # Act / Assert
    expect { described_class.new(empty, connector: counting_connector).resolve! }
      .to raise_error(an_object_having_attributes(kind: :validation))
  end

  it 'treats a malformed session payload as a protocol error instead of storing garbage' do
    # Arrange
    record = connection
    broken = Class.new(Autonomia::Insurance::Connector::Client) do
      def open_session(**) = { 'platform' => 'agger' }
    end.new

    # Act / Assert
    expect { described_class.new(record, connector: broken).resolve! }
      .to raise_error(an_object_having_attributes(kind: :protocol))
    expect(record.reload.session).to be_nil
  end

  # O AVISO DE "CONTA EM USO" QUE MENTIA (entrega 16, termo 5).
  #
  # O portal devolve "Ja existe uma sessao ativa com esse usuario" no MESMO 201 do login bem-sucedido,
  # em TODO login: 6 de 6 nos logins SIMULTANEOS medidos em 10/09/2026, e tambem nos sete logins em
  # sequencia de 05/09. E aviso de REUSO da sessao que ja existe — o portal compartilha uma sessao por
  # login —, nunca prova de que outra pessoa esteja na conta.
  #
  # Nos gravavamos isso em `account_already_active` e a tela de Conexoes afirmava ao corretor que a
  # conta estava em uso em outro lugar. Depois do primeiro login da conta o alerta ficava ligado para
  # sempre, e a "outra pessoa" era, quase sempre, a nossa propria sessao anterior (healthcheck de 30
  # em 30 minutos, polling de cotacao de poucos em poucos segundos).
  #
  # NADA NO PAYLOAD DISCRIMINA quem abriu a sessao, entao o aviso morre em vez de ser refinado.
  describe 'o aviso de conta em uso nao e gravado (termo 5 da entrega 16)' do
    def conector_que_avisa(already)
      payload = { 'platform' => 'agger', 'data' => { 'token' => 'x' },
                  'expires_at' => 3.hours.from_now.utc.iso8601,
                  'session_started_at' => '2026-09-06T14:02:00Z' }
      payload['already_active'] = already unless already.nil?
      instance_double(Autonomia::Insurance::Connector::Mock, open_session: payload)
    end

    it 'nao grava aviso nenhum quando o portal diz que ja havia sessao ativa, porque ele diz isso em todo login' do
      # Arrange
      conexao = connection

      # Act
      described_class.new(conexao, connector: conector_que_avisa(true)).resolve!

      # Assert — a sessao abre, e nada e afirmado sobre quem mais estaria na conta
      expect(conexao.reload.metadata.to_h).not_to have_key('account_already_active')
      expect(conexao.session).to be_present
    end

    it 'apaga o aviso que uma versao anterior gravou, em vez de deixar a afirmacao falsa no banco' do
      # Arrange — linha que passou por uma versao que ainda gravava o aviso
      conexao = connection
      conexao.merge_metadata!('account_already_active' => { 'observed_at' => '2026-09-05T10:00:00Z' })

      # Act
      described_class.new(conexao, connector: conector_que_avisa(true)).resolve!

      # Assert
      expect(conexao.reload.metadata.to_h).not_to have_key('account_already_active')
    end

    it 'apaga so o aviso: o resto de metadata continua inteiro' do
      # Arrange — `metadata` e jsonb compartilhado: a comissao da corretora mora no mesmo campo, e
      # apagar de mais aqui custaria dinheiro do cliente.
      conexao = connection
      conexao.merge_metadata!('account_already_active' => { 'observed_at' => '2026-09-05T10:00:00Z' },
                              'comissao' => { 'auto' => 12 })

      # Act
      described_class.new(conexao, connector: conector_que_avisa(true)).resolve!

      # Assert
      expect(conexao.reload.metadata.to_h['comissao']).to eq('auto' => 12)
      expect(conexao.metadata.to_h).not_to have_key('account_already_active')
    end
  end
end
