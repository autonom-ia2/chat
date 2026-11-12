# A situação de uma lista trazida (#2896), nas palavras da tela, tirada do estado da importação de contatos:
# - confirmada, na fila ou gravando: "trazendo";
# - gravada (com ou sem linha que falhou): "pronto"; com o desfazer rodando, "desfazendo"; desfeita, "desfeito";
# - a gravação começou e quebrou: "falhou" (a tela oferece "Tentar de novo" quando a importação ainda pode continuar).
# Rascunho (enviada, lendo, pronta para conferir, leitura que falhou) não é lista trazida: fica fora do histórico.
module Relacionamentos::Trazer::Situacao
  TRAZENDO = %w[confirmed queued importing].freeze
  GRAVADA = %w[completed completed_with_failures].freeze
  DEPOIS_DE_GRAVADA = { 'pending' => 'pronto', 'failed' => 'pronto', 'processing' => 'desfazendo', 'completed' => 'desfeito' }.freeze
  ACABOU = DEPOIS_DE_GRAVADA.values.uniq.freeze
  TUDO = 100

  module_function

  def de(importacao)
    return 'trazendo' if TRAZENDO.include?(importacao.status)
    return DEPOIS_DE_GRAVADA.fetch(importacao.undo_status) if GRAVADA.include?(importacao.status)

    'falhou' if importacao.failed? && importacao.import_started_at.present?
  end

  # As importações do escopo que têm situação: as que a tela mostra como lista trazida.
  def no_historico(importacoes)
    importacoes.where(status: TRAZENDO + GRAVADA).or(importacoes.where(status: :failed).where.not(import_started_at: nil))
  end

  # Quanto da lista já passou pela gravação. `feitas` são as linhas gravadas mais as que falharam.
  def porcentagem(situacao, feitas, total)
    return TUDO if ACABOU.include?(situacao)
    return 0 unless total.positive?

    [feitas * TUDO / total, TUDO].min
  end
end
