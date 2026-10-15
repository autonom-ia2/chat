# O marco "assunto decidido" de uma conversa (#1606, contrato com o Agentes IA): até qual mensagem do cliente o assunto
# já foi decidido E, na ordem do turno, o dono já foi trocado (o ResponsibleAgentSync roda em linha antes do marco).
# O ReplyJob do Agentes IA espera o marco alcançar a mensagem do turno antes de responder, com teto de 20 s.
#
#   Crm::Subjects::Marco.gravar(conversation_id, message_id)  # só avança, nunca volta
#   Crm::Subjects::Marco.decidido_ate(conversation_id)        # -> Integer | nil
#   Crm::Subjects::Marco.decidido_ate?(conversation_id, message_id)
#
# Chave Redis e não atributo da conversa: gravar na conversa dispararia conversation_updated a cada rajada.
module Crm::Subjects::Marco
  VALIDADE = 10.minutes
  # Tentativas do avanço otimista (WATCH/MULTI): outro job gravando ao mesmo tempo faz a transação abortar e tentar de
  # novo.
  TENTATIVAS = 5

  module_function

  # Só para frente (o job de uma mensagem velha que termina depois não volta o marco) e renova a validade. WATCH/MULTI,
  # como o Redis::Alfred.delete_if_equals: se outro job gravou no meio, tenta de novo.
  def gravar(conversation_id, message_id)
    chave = chave(conversation_id)
    Redis::Alfred.with do |conn|
      TENTATIVAS.times do
        gravado = conn.watch(chave) do
          novo = [conn.get(chave).to_i, message_id.to_i].max
          conn.multi { |transacao| transacao.set(chave, novo, ex: VALIDADE.to_i) }
        end
        break if gravado
      end
    end
  end

  def decidido_ate(conversation_id)
    valor = Redis::Alfred.get(chave(conversation_id))
    valor.present? ? valor.to_i : nil
  end

  def decidido_ate?(conversation_id, message_id)
    ate = decidido_ate(conversation_id)
    ate.present? && ate >= message_id.to_i
  end

  def chave(conversation_id)
    "crm:assunto_decidido:#{conversation_id}"
  end
end
