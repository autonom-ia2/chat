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
  PREFIXO = 'autonomia:guide:pedido:'.freeze
  # Folga larga sobre o tempo máximo do laço (`MAX_SEGUNDOS_DE_FERRAMENTA`, 180s)
  # para a tela ainda achar a resposta se demorar a buscar.
  VALIDADE = 10.minutes

  PENDENTE = 'pending'.freeze
  PRONTO = 'done'.freeze
  FALHOU = 'failed'.freeze

  class << self
    # -> id do pedido, que a tela usa para buscar a resposta.
    def abrir(account:, user:)
      id = SecureRandom.uuid
      gravar(id, { 'status' => PENDENTE, 'account_id' => account.id, 'user_id' => user.id })
      id
    end

    def concluir(id, resultado)
      atualizar(id) { |pedido| pedido.merge('status' => PRONTO, 'resultado' => resultado) }
    end

    def falhar(id)
      atualizar(id) { |pedido| pedido.merge('status' => FALHOU) }
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

      { 'status' => pedido['status'] }.merge(pedido['resultado'].to_h)
    end

    private

    def chave(id)
      "#{PREFIXO}#{id}"
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
