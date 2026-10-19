# Follow-up automático que não saiu vira aviso para a equipe (DueProcessor, `:fallback`): o modo troca para só-lembrete e a
# descrição passa a explicar o motivo. Quando o motivo é uma falha passageira da Meta, reagendar o aviso precisa tentar o
# envio de novo (#1624, ponto (b) do #1734). Por isso o que o aviso trocou fica guardado no metadata, escrita só do servidor
# (MetadataSanitizer::SERVER_OWNED_KEYS), e o Rescheduler o devolve.
module Crm::FollowUps::CallbackFallback
  KEY = 'callback_original'.freeze
  FALLBACK_KEY = 'callback_fallback'.freeze
  # A Meta não respondeu agora; o motivo não diz nada sobre o follow-up em si. Qualquer outro (sem modelo, em análise,
  # categoria, campo sem valor) pede decisão de uma pessoa: reagendar continua só lembrete.
  TRANSITORIOS = %w[conferencia_sem_meta meta_fora].freeze

  module_function

  # O que o aviso vai trocar, para devolver depois. Só chega aqui follow-up que era envio automático (DueProcessor#dispatch).
  def original_of(follow_up)
    { KEY => { 'automation_mode' => follow_up.automation_mode, 'description' => follow_up.description } }
  end

  # Aviso atrasado, caído por falha passageira, de um envio que era automático, sem outro envio automático do mesmo tipo
  # esperando no card (o cliente receberia duas mensagens).
  def restorable?(follow_up)
    metadata = follow_up.metadata.to_h
    follow_up.overdue? && follow_up.reminder_only? && metadata[KEY].is_a?(Hash) &&
      TRANSITORIOS.include?(metadata[FALLBACK_KEY].to_s) && !other_automatic_send_pending?(follow_up)
  end

  # #1855: é ou foi envio ao cliente: mensagem automática, ou o aviso de uma que caiu para a equipe (tem o original guardado).
  # O "Passar os meus para amanhã" do calendário deixa esses de fora: um clique em lote nunca manda mensagem a cliente.
  def automatic_send?(follow_up)
    follow_up.auto_send_message? || follow_up.metadata.to_h[KEY].is_a?(Hash)
  end

  def other_automatic_send_pending?(follow_up)
    Crm::FollowUp.pending.auto_send_message.where(card_id: follow_up.card_id)
                 .where("metadata ->> 'source' = ?", follow_up.metadata.to_h['source']).where.not(id: follow_up.id).exists?
  end

  # Atributos que devolvem o envio automático: o modo e a descrição de antes, sem as marcas do aviso. Quem já dispensou o
  # aviso volta a ser avisado se o envio cair de novo (a dispensa valia para aquele aviso, não para o próximo).
  def restoring_attributes(follow_up)
    metadata = follow_up.metadata.to_h
    original = metadata.fetch(KEY)
    { automation_mode: original['automation_mode'], description: original['description'],
      metadata: metadata.except(KEY, FALLBACK_KEY, Crm::FollowUps::ReminderDismisser::METADATA_KEY) }
  end
end
