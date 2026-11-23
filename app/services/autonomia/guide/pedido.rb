# Uma pergunta ao Guia enquanto ele trabalha (issue #572).
#
# O Guia respondia DENTRO da requisição, e o `rack-timeout` de produção mata
# qualquer requisição aos 15 segundos. Medido em 21/09/2026, logo depois do
# deploy da #571:
#
#   "quantas conversas abertas eu tenho?"  1 leitura    9.399 ms -> 200
#   "me fala sobre minhas conversas"        2 leituras  15.255 ms -> 500
#
# Agora a requisição só abre o pedido e devolve na hora. Quem responde é um job,
# e a tela busca o resultado por aqui. O teto de 15s deixa de existir para o
# Guia, e ele pode ler quantas vezes precisar.
#
# Mora no Redis, com validade, e não no banco: é estado de minutos, que ninguém
# consulta depois. Uma tabela para isto seria migration em produção para
# guardar lixo.
#
# O pedido é de QUEM perguntou. Outra pessoa — mesmo da mesma conta — não lê a
# resposta de ninguém: ela pode conter dado que só quem perguntou tem permissão
# de ver, porque a leitura saiu com a permissão dele.
class Autonomia::Guide::Pedido
  class TravaOcupada < StandardError; end

  PREFIXO = 'autonomia:guide:pedido:'.freeze
  # Folga larga sobre o tempo máximo do laço (`MAX_SEGUNDOS_DE_FERRAMENTA`, 180s)
  # para a tela ainda achar a resposta se demorar a buscar.
  VALIDADE = 30.minutes

  PENDENTE = 'pending'.freeze
  PRONTO = 'done'.freeze
  FALHOU = 'failed'.freeze

  # O nome de uma ferramenta cabe com folga; o teto só impede gravar lixo grande no Redis.
  MAX_ETAPA = 60
  # A trava entre a mensagem que chega e o fim do turno dura o tempo de mexer em duas chaves do Redis.
  TEMPO_DA_TRAVA = 10
  TENTATIVAS_DA_TRAVA = 20
  ESPERA_DA_TRAVA = 0.05

  class << self
    # -> id do pedido, que a tela usa para buscar a resposta.
    def abrir(account:, user:, id: SecureRandom.uuid)
      gravar(id, { 'status' => PENDENTE, 'account_id' => account.id, 'user_id' => user.id })
      id
    end

    # A pessoa escreveu de novo enquanto o Guia ainda trabalha neste pedido. A mensagem não vira pergunta separada:
    # entra na fila deste pedido, e o Guia a lê na próxima rodada de ferramentas (`Contexto#mensagens_novas`) e decide
    # o que fazer — parar, mudar o caminho ou seguir. Se ela chegar depois da última rodada, o fim do turno a manda
    # adiante como a pergunta seguinte (`ChatJob#encerrar`).
    #
    # `nova` é o pedido da mensagem nova, que a tela acompanha para saber o que aconteceu com ela; o turno dela já
    # existe antes daqui, para o Guia poder juntá-lo assim que ler. -> false quando este pedido já terminou (ou é de
    # outra pessoa): aí a mensagem é uma pergunta comum.
    def acrescentar(id, account:, user:, nova:, mensagem:)
      com_trava(id) do
        pedido = carregar(id)
        next false unless pedido && pedido['status'] == PENDENTE
        next false unless pedido['account_id'] == account.id && pedido['user_id'] == user.id

        abrir(account: account, user: user, id: nova)
        Redis::Alfred.lpush(chave_das_juntas(id), { 'id' => nova, 'texto' => mensagem.to_s }.to_json)
        Redis::Alfred.expire(chave_das_juntas(id), VALIDADE.to_i)
        true
      end
    end

    # As mensagens que esperam o Guia ler, na ordem em que chegaram; saem da fila ao serem lidas.
    # -> [{ 'id' => pedido da mensagem, 'texto' => o que ela escreveu }]
    def retirar_juntas(id)
      juntas = []
      while (bruto = Redis::Alfred.rpop(chave_das_juntas(id)))
        junta = ler_junta(bruto)
        juntas << junta if junta
      end
      juntas
    end

    # O fim do turno e a mensagem que chega disputam a mesma fila: sem a trava, uma mensagem gravada entre a última
    # leitura do Guia e o "pronto" do pedido ficaria esquecida. Quem chega com a trava ocupada espera um instante.
    def com_trava(id)
      trava = Redis::LockManager.new
      chave = "#{chave(id)}:trava"
      TENTATIVAS_DA_TRAVA.times do
        resultado = nil
        return resultado if trava.with_lock(chave, TEMPO_DA_TRAVA) { resultado = yield }

        sleep(ESPERA_DA_TRAVA)
      end
      raise TravaOcupada, chave
    end

    # O que o Guia está fazendo agora: o nome da última ferramenta chamada. A tela mostra a frase dela ("Lendo os
    # dados da conta…") enquanto espera. Chave separada: o fim do turno reescreve o pedido inteiro.
    def anotar_etapa(id, ferramenta)
      return if id.blank? || ferramenta.blank?

      Redis::Alfred.set(chave_da_etapa(id), ferramenta.to_s.first(MAX_ETAPA), ex: VALIDADE.to_i)
    end

    def concluir(id, resultado)
      atualizar(id) { |pedido| pedido.merge('status' => PRONTO, 'resultado' => resultado) }
    end

    # `extra`: a pergunta seguinte, quando a pessoa escreveu de novo durante o turno que falhou (`ChatJob#encerrar`).
    def falhar(id, extra = {})
      atualizar(id) { |pedido| pedido.merge('status' => FALHOU, 'resultado' => extra.presence).compact }
    end

    # O que a tela recebe: o estado e, quando pronto, a resposta. Nunca o dono —
    # a conferência de dono é aqui, e o número da conta não serve à tela.
    #
    # Pedido de outra pessoa se comporta EXATAMENTE como pedido que não existe:
    # dizer "existe, mas não é seu" confirmaria a quem tenta adivinhar que acertou.
    def ler(id, account:, user:)
      pedido = carregar(id)
      return nil if pedido.nil?
      return nil unless pedido['account_id'] == account.id && pedido['user_id'] == user.id

      { 'status' => pedido['status'] }.merge(pedido['resultado'].to_h).merge(etapa(id, pedido))
    end

    private

    def chave(id)
      "#{PREFIXO}#{id}"
    end

    def chave_das_juntas(id) = "#{chave(id)}:juntas"

    def chave_da_etapa(id) = "#{chave(id)}:etapa"

    # A etapa só interessa enquanto o Guia trabalha.
    def etapa(id, pedido)
      return {} unless pedido['status'] == PENDENTE

      atual = Redis::Alfred.get(chave_da_etapa(id))
      atual.present? ? { 'etapa' => atual } : {}
    end

    def ler_junta(bruto)
      junta = JSON.parse(bruto)
      junta.is_a?(Hash) ? junta : nil
    rescue JSON::ParserError
      nil
    end

    def carregar(id)
      bruto = Redis::Alfred.get(chave(id.to_s))
      bruto.present? ? JSON.parse(bruto) : nil
    rescue JSON::ParserError
      nil
    end

    def gravar(id, pedido)
      Redis::Alfred.set(chave(id), pedido.to_json, ex: VALIDADE.to_i)
    end

    # Só atualiza o que existe. Um job que terminou depois do pedido vencer não
    # ressuscita a chave — a tela já desistiu dela.
    def atualizar(id)
      pedido = carregar(id)
      return if pedido.nil?

      gravar(id, yield(pedido))
    end
  end
end
