# A situação de uma lista trazida (#2896), nas palavras da tela, tirada do estado da importação de contatos:
# - confirmada, na fila ou gravando: "trazendo";
# - gravada (com ou sem linha que falhou): "pronto"; com o desfazer rodando, "desfazendo"; desfeita, "desfeito";
# - a gravação começou e quebrou: "falhou" (a tela oferece "Tentar de novo" quando a importação ainda pode continuar, e
#   "Desfazer", para tirar quem ela chegou a pôr); com o desfazer rodando, "desfazendo"; desfeita, "desfeito";
# - o fechamento da conferência quebrou vezes demais (ContactImports::Trazer::Fechamentos): também "falhou", e
#   "Tentar de novo" fecha de novo.
# Rascunho (enviada, lendo, pronta para conferir, leitura que falhou) não é lista trazida: fica fora do histórico.
module Relacionamentos::Trazer::Situacao
  TRAZENDO = %w[confirmed queued importing].freeze
  GRAVADA = %w[completed completed_with_failures].freeze
  DEPOIS_DE_GRAVADA = { 'pending' => 'pronto', 'failed' => 'pronto', 'processing' => 'desfazendo', 'completed' => 'desfeito' }.freeze
  # A lista que quebrou no meio também pode ser desfeita (Relacionamentos::Trazer::Desfazer.pode?).
  DEPOIS_DE_QUEBRAR = DEPOIS_DE_GRAVADA.slice('processing', 'completed').freeze
  ACABOU = DEPOIS_DE_GRAVADA.values.uniq.freeze
  TUDO = 100

  module_function

  def de(importacao)
    return 'trazendo' if TRAZENDO.include?(importacao.status)
    return DEPOIS_DE_GRAVADA.fetch(importacao.undo_status) if GRAVADA.include?(importacao.status)

    return unless importacao.failed?
    return DEPOIS_DE_QUEBRAR.fetch(importacao.undo_status, 'falhou') if importacao.import_started_at.present?

    'falhou' if ContactImports::Trazer::Fechamentos.desistiu?(importacao)
  end

  # As importações do escopo que têm situação: as que a tela mostra como lista trazida.
  def no_historico(importacoes)
    quebradas = importacoes.where(status: :failed)
    importacoes.where(status: TRAZENDO + GRAVADA).or(quebradas.where.not(import_started_at: nil)).or(
      quebradas.where("validation_summary ->> 'import_error' = ?", ContactImports::Trazer::Fechamentos::ERRO)
    )
  end

  # "Tentar de novo" serve: a gravação que parou no meio continua, e o fechamento que desistiu é tentado de novo.
  # O fechamento que desistiu numa conferência vencida não: os consertos já sumiram.
  def pode_tentar?(importacao)
    return true if importacao.import_resumable?

    ContactImports::Trazer::Fechamentos.desistiu?(importacao) && !ContactImports::Trazer::Conferencia.vencida?(importacao)
  end

  # Quanto da lista já passou pela gravação. `feitas` são as linhas gravadas mais as que falharam.
  def porcentagem(situacao, feitas, total)
    return TUDO if ACABOU.include?(situacao)
    return 0 unless total.positive?

    [feitas * TUDO / total, TUDO].min
  end
end
