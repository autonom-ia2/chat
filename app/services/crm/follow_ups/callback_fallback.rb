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

  # Aviso atrasado, caído por falha passageira, de um envio que era automático.
  def restorable?(follow_up)
    metadata = follow_up.metadata.to_h
    follow_up.overdue? && follow_up.reminder_only? && metadata[KEY].is_a?(Hash) && TRANSITORIOS.include?(metadata[FALLBACK_KEY].to_s)
  end

  # Atributos que devolvem o envio automático: o modo e a descrição de antes, sem as marcas do aviso.
  def restoring_attributes(follow_up)
    metadata = follow_up.metadata.to_h
    original = metadata.fetch(KEY)
    { automation_mode: original['automation_mode'], description: original['description'],
      metadata: metadata.except(KEY, FALLBACK_KEY) }
  end
end
