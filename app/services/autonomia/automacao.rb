# Automação livre (#2414). ADR: docs/automacao/ADR-001-motor-de-automacao-livre.md.
module Autonomia::Automacao
  # F1 (#2443): cadeia comum dos três motores e "mover cria o card". Desligada, os motores antigos fazem o de antes.
  FLAG_FUNDACAO = 'automacao_fundacao'.freeze

  def self.fundacao?(account)
    account.present? && account.feature_enabled?(FLAG_FUNDACAO)
  end
end
