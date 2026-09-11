# A SESSÃO COMPARTILHADA da conexão com o portal.
#
# CORREÇÃO DE 11/09/2026 — este cabeçalho dizia "o AGGER aceita uma sessão viva por login: abrir
# outra invalida a anterior". É FALSO, e foi medido duas vezes contra o portal real:
#   - 05/09: sete logins EM SEQUÊNCIA devolveram o MESMO id de sessão, e o token do primeiro
#     continuou respondendo 200 depois de todos os outros. Virou canário vivo em
#     `autonomia-adapters/test/contract/agger.sessao-unica.live.test.ts`;
#   - 10/09, agora sob CORRIDA: seis logins SIMULTÂNEOS coexistiram (um id de sessão para os seis,
#     zero precisaram derrubar a anterior), e doze sessões da mesma conta fizeram 1.202 chamadas
#     autenticadas em 30 s sem uma falha, com mediana de latência IGUAL à de seis sessões — não há
#     disputa (`autonomia-adapters/scripts/discovery/provar-sessoes-paralelas.ts`).
#
# A frase antiga importa porque é ela que faria o próximo engenheiro serializar cotação por
# corretora — e essa fila nos tornaria o gargalo que o portal não é. Uma corretora tem vários
# clientes cotando ao mesmo tempo; cotar em paralelo é requisito de produto, não conveniência.
#
# ENTÃO POR QUE A SESSÃO CONTINUA MORANDO NA CONEXÃO (conta + provider), e não em quem chama? Por
# economia e clareza, não por exclusividade:
#   - o portal avisa "já existe uma sessão ativa" em TODO login e devolve a MESMA sessão. Abrir uma
#     por chamador seria pagar um login de até 60 s (`Http::READ_TIMEOUT`) dezenas de vezes por
#     cotação para receber de volta o que já tínhamos;
#   - uma cotação consulta o resultado de poucos em poucos segundos por até 7 minutos, e o
#     healthcheck varre todas as conexões de 30 em 30 minutos: sem compartilhar, cada passada dessas
#     seria um login;
#   - guardar a sessão em UM lugar é o que faz `session_expires_at` significar alguma coisa.
#
# CONCORRÊNCIA: o caminho feliz não pega lock (a sessão viva é lida direto). Só quem precisa ABRIR
# entra no `with_lock` e RECHECA lá dentro — duas cotações que começam juntas fazem um login só, e a
# segunda encontra a sessão que a primeira acabou de gravar. Isso é economia de login, e NÃO
# serialização de cotação: quem já tem sessão viva não passa por lock nenhum.
class Autonomia::Insurance::Connections::Session
  def initialize(connection, connector: ::Autonomia::Insurance::Connector.client)
    @connection = connection
    @connector = connector
  end

  # -> Hash da sessão. Levanta Connector::Error quando não dá para abrir (o chamador traduz em
  # status da conexão, como o Sync já faz).
  def resolve!
    return @connection.session if @connection.session_live?

    open_under_lock!
    session = @connection.session
    raise ::Autonomia::Insurance::Connector::Error.new(:auth_required, 'session unavailable') if session.blank?

    session
  end

  # O portal recusou o que guardamos (sessão encerrada antes do prazo, ou substituída por um login
  # feito fora daqui). Esquece e abre outra. -> Hash da nova sessão.
  def renew!
    @connection.forget_session!
    resolve!
  end

  # Roda o bloco com a sessão da conexão e, se o PORTAL recusar essa sessão, esquece, abre outra e
  # tenta UMA vez. -> o que o bloco devolver.
  #
  # `session_live?` só sabe do PRAZO QUE NÓS GRAVAMOS, e prazo gravado não é prova: a sessão pode ter
  # morrido antes dele (o portal encurtar a validade, a limpeza noturna — janelas longas nunca foram
  # observadas, e a medição de 10/09 durou minutos). Quando isso acontece, a linha fica com uma
  # sessão que PARECE viva e toda chamada morre em 403 até o prazo vencer.
  #
  # (Correção de 11/09/2026: aqui se lia "alguém entrou no portal pelo navegador e derrubou a nossa —
  # o AGGER aceita uma sessão por login". Medido e falso: logins da mesma conta compartilham a
  # sessão, e nenhum token anterior foi invalidado. A causa PROVADA do incidente de 05/09 também era
  # outra, e já está corrigida — o handler redigia o token e mandava a palavra `<REDACTED>` como
  # `Authorization`. O motivo honesto é o do parágrafo acima, e ele basta para a renovação existir.)
  #
  # UMA tentativa, não um laço: se o login novo também for recusado, o problema é a credencial, e
  # insistir só multiplica login no portal.
  def with_fresh_session
    yield resolve!
  rescue ::Autonomia::Insurance::Connector::Error => e
    raise unless e.kind == :auth_required && @connection.session.present?

    yield renew!
  end

  # A SESSÃO QUE JÁ ESTÁ VIVA, e nenhuma outra — para quem roda DENTRO DO TURNO, com o modelo
  # esperando (a consulta de placa da conferência e a ferramenta `consultar_placa`, entrega 2).
  # Abrir sessão é login no portal com o teto de 60 s do conector (`Http::READ_TIMEOUT`), e o turno
  # não pode esperar isso: `bound_async_spec` guarda que "a 60s call cannot hold the turn". Sem
  # sessão viva o bloco não roda e o retorno é nil; se o portal recusar a que parecia viva, o erro
  # sobe SEM renovação — quem abre e renova é o healthcheck e o job do envio, fora do turno.
  def with_live_session
    return nil unless @connection.session_live?

    yield @connection.session
  end

  private

  # O RECHECK dentro do lock é o que faz duas chamadas concorrentes gerarem UM login: a segunda
  # entra, encontra a sessão que a primeira acabou de gravar, e não abre outra.
  #
  # (Correção de 04/09/2026: este comentário afirmava que `return` dentro do `with_lock` dispararia
  # ROLLBACK e descartaria a sessão. Medido no Rails 7.2.3.1 desta aplicação — não dispara, o dado
  # persiste. Era regra de Rails antigo repetida sem conferir. O estilo sem `return` aqui é
  # preferência de leitura, não requisito de correção.)
  def open_under_lock!
    @connection.with_lock do
      open! unless @connection.session_live?
    end
  end

  def open!
    raise ::Autonomia::Insurance::Connector::Error.new(:validation, 'credentials missing') unless @connection.credentials_present?

    payload = @connector.open_session(provider: @connection.provider, username: @connection.username,
                                      password: @connection.password)
    unless payload.is_a?(Hash) && payload['data'].is_a?(Hash)
      raise ::Autonomia::Insurance::Connector::Error.new(:protocol, 'session payload is not a hash')
    end

    @connection.store_session!(payload['data'], expires_at: payload['expires_at'],
                                                account_label: payload['account_label'].to_s.truncate(120).presence)
    esquecer_aviso_de_conta_em_uso!
  end

  # O AVISO DE "CONTA EM USO" QUE MENTIA — o que sobrou do critério 1.5.
  #
  # O portal devolve "Já existe uma sessão ativa com esse usuário" no MESMO 201 do login
  # bem-sucedido, em TODO login: 6 de 6 nos logins simultâneos de 10/09/2026, e também nos sete
  # logins em sequência de 05/09. É aviso de REUSO da sessão que ele compartilha, não notícia de que
  # outra pessoa esteja na conta. Nós gravávamos isso em `account_already_active` e a tela de
  # Conexões AFIRMAVA ao corretor que a conta estava sendo usada em outro lugar — depois do primeiro
  # login da conta, para sempre, e quase sempre a "outra pessoa" era a nossa própria sessão anterior
  # (healthcheck de 30 em 30 minutos, polling de cotação de poucos em poucos segundos).
  #
  # NADA NO PAYLOAD DISCRIMINA, e é por isso que o aviso morre em vez de ser refinado:
  #   - `already_active` é a presença do texto na mensagem, e a mensagem vem sempre;
  #   - `session_started_at` é o `createdAt` da sessão COMPARTILHADA — foi o mesmo valor para os seis
  #     logins simultâneos. Diz quando a sessão começou, nunca quem a abriu;
  #   - comparar esse instante com o nosso último login também não serve: nós abrimos sessão o tempo
  #     todo, e a conta é quase sempre a nossa. Seria a mesma afirmação, agora com aritmética por
  #     cima.
  # Alarme que não discrimina é alarme falso, e alarme falso permanente treina o corretor a ignorar
  # a tela inteira.
  #
  # Aqui só se APAGA o que uma versão anterior gravou. Não é limpeza cosmética: enquanto a chave
  # existir no banco, ela é uma afirmação falsa esperando o próximo leitor.
  def esquecer_aviso_de_conta_em_uso!
    @connection.forget_metadata!('account_already_active')
  end
end
