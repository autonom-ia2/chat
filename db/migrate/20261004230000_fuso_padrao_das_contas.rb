# Fuso de São Paulo nas contas que não têm nenhum (decisão do Rodrigo, 04/10/2026).
#
# A conta guarda o fuso em dois lugares: `custom_attributes['timezone']`, o que a tela de Primeiros
# passos grava e o Guia lê, e `settings['reporting_timezone']`, o dos relatórios e do CRM. Em produção
# nenhuma conta tinha o segundo e só 6 de 22 tinham o primeiro: o Guia perguntava o fuso em todo pedido
# com horário, e o que lê o fuso vazio caía em UTC (3 horas à frente de Brasília).
#
# Só preenche o que está VAZIO: fuso escolhido pela corretora fica como está. Idempotente.
# O `down` não desfaz: não há como saber qual conta já tinha escolhido São Paulo por conta própria.
class FusoPadraoDasContas < ActiveRecord::Migration[7.1]
  FUSO = 'America/Sao_Paulo'.freeze

  def up
    execute(<<~SQL.squish)
      UPDATE accounts
      SET custom_attributes = COALESCE(custom_attributes, '{}'::jsonb) || jsonb_build_object('timezone', '#{FUSO}')
      WHERE COALESCE(custom_attributes ->> 'timezone', '') = ''
    SQL
    execute(<<~SQL.squish)
      UPDATE accounts
      SET settings = COALESCE(settings, '{}'::jsonb) || jsonb_build_object('reporting_timezone', '#{FUSO}')
      WHERE COALESCE(settings ->> 'reporting_timezone', '') = ''
    SQL
  end

  def down; end
end
