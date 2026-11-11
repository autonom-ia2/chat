# Automação livre (#2414). ADR: docs/automacao/ADR-001-motor-de-automacao-livre.md.
module Autonomia::Automacao
  # F1 (#2443): cadeia comum dos três motores e "mover cria o card". Desligada, os motores antigos fazem o de antes.
  FLAG_FUNDACAO = 'automacao_fundacao'.freeze

  def self.fundacao?(account)
    account.present? && account.feature_enabled?(FLAG_FUNDACAO)
  end

  # #2889: a porta da Automação. Com ela (e o editor, que a API das automações pede), o Guia monta no motor novo.
  FLAGS_DA_PORTA = %w[automacao_porta automacao_editor].freeze

  def self.porta?(account)
    account.present? && FLAGS_DA_PORTA.all? { |flag| account.feature_enabled?(flag) }
  end
end
