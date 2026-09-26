# AS RECUSAS RECENTES DE UMA CONVERSA, para a nota da equipe no encaminhamento (conversa 7057, 24/09/2026).
#
# A busca de atividade estourou o tempo duas vezes, a Lia disse ao cliente que alguém da equipe assumia, e a equipe
# recebeu a conversa sem saber por quê: a recusa só ia para o log. Aqui cada recusa com conversa deixa o CÓDIGO do
# motivo (nunca dado do cliente, nunca texto da conversa) numa lista curta no Redis, que o encaminhamento recolhe
# (`NotaDoEncaminhamento`) e apaga. Sem encaminhamento, a lista expira sozinha.
#
# NUNCA LEVANTA, como o próprio registro da recusa: é cortesia sobre um caminho que já deu errado.
module Autonomia::Agents::Tools::RecusasRecentes
  CHAVE = 'autonomia:recusas_recentes:%<conversa>d'.freeze
  VALIDADE = 30.minutes
  TETO = 20
  # SÓ FALHA DE FORA (revisão da chat#665): o que a Lia não tinha como resolver e que explica um encaminhamento. Recusa
  # do fluxo normal (faltam dados, pedido repetido, conferência que pediu outro valor) acontece em cotação que deu
  # certo, e na nota enganaria a equipe.
  NA_NOTA = %w[tool_execution_error tool_http_error capabilities_unavailable async_desligado conexao_indisponivel
               formulario_indisponivel especialista_sem_credencial especialista_sem_resposta especialista_falhou
               especialista_nao_concluiu consulta_de_placa_indisponivel consulta_de_cep_indisponivel
               busca_de_atividade_indisponivel].freeze

  # O RAMO QUE A PESSOA PEDIU E A IA NÃO COTA (conversa 7150, 26/09/2026): a Lia encaminha para a equipe, e a equipe
  # precisa saber qual seguro a pessoa quer. Guardado como `ramo_pedido:<ramo>`, na mesma lista, para sair na mesma nota.
  PREFIXO_DO_RAMO = 'ramo_pedido:'.freeze

  module_function

  def anotar(conversa_id, motivo)
    return if conversa_id.blank? || NA_NOTA.exclude?(motivo)

    guardar(conversa_id, motivo)
  end

  # `ramo` é o código do produto como a conexão o escreve (`vida`, `vida_global`), nunca texto da pessoa: quem chama
  # confere que ele está na lista da conexão. O que não tem forma de código não é guardado. Nunca levanta.
  def anotar_ramo(conversa_id, ramo)
    codigo = ::Autonomia::Agents::Tools::Recusa.codigo(ramo)
    return if conversa_id.blank? || codigo == '-'

    guardar(conversa_id, "#{PREFIXO_DO_RAMO}#{codigo}")
  end

  def guardar(conversa_id, valor)
    chave = format(CHAVE, conversa: conversa_id)
    Redis::Alfred.lpush(chave, valor)
    Redis::Alfred.with { |redis| redis.ltrim(chave, 0, TETO - 1) }
    Redis::Alfred.expire(chave, VALIDADE.to_i)
    nil
  rescue StandardError
    nil
  end

  # -> os motivos, do mais antigo ao mais novo, e a lista apagada. [] sem nada ou se o Redis falhar. Ler e apagar numa
  # operação só: o sinal da Lia e o encaminhamento do CRM podem chegar juntos, e só um leva a lista.
  def retirar(conversa_id)
    chave = format(CHAVE, conversa: conversa_id)
    motivos, = Redis::Alfred.with do |redis|
      redis.multi do |tx|
        tx.lrange(chave, 0, -1)
        tx.del(chave)
      end
    end
    Array(motivos).reverse
  rescue StandardError
    []
  end
end
