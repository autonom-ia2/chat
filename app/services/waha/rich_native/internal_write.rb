# Marca, só em memória, de uma mensagem que o PRÓPRIO chat2you monta com as chaves que ele grava (chat#1709, fase 3):
# o voto da enquete do plano B do Híbrido (WhatsappHybrid::RichNative::PollVoteJob) já nasce com `selected_options` e,
# no voto retirado, `c2y_hidden`. Sem a marca, Waha::RichNative::ContractGuard tiraria essas chaves, como tira de
# qualquer mensagem criada pela API. A marca não é coluna nem chave: nenhum caminho externo consegue mandá-la.
module Waha::RichNative::InternalWrite
  module_function

  def mark!(message)
    message.instance_variable_set(:@c2y_internal_write, true)
    message
  end

  def internal?(message)
    message.instance_variable_get(:@c2y_internal_write) == true
  end
end
