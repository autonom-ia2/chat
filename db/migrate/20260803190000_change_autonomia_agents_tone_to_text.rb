class ChangeAutonomiaAgentsToneToText < ActiveRecord::Migration[7.1]
  # `tone` nasceu como string, o que o ApplicationRecord trata como coluna de 255 caracteres
  # (MAX_STRING_COLUMN_LENGTH). O Construtor gera o tom em linguagem natural e passava desse teto
  # ao receber pedidos com mais nuance, derrubando a gravação INTEIRA da config do agente — o
  # ajuste do dono era descartado em silêncio. Como text, o campo passa a caber o que o Construtor
  # escreve; o teto real vira a validação explícita do model (Agent::MAX_TONE_LENGTH).
  def up
    change_column :autonomia_agents, :tone, :text
  end

  def down
    change_column :autonomia_agents, :tone, :string
  end
end
