# PERFIL DA EMPRESA PESQUISADA NA PROSPECÇÃO (chat#679, E3 frente C).
#
# Um por CNPJ, sem conta: é dado de cadastro público (Receita, pelas fontes gratuitas), e o mesmo lugar achado por duas
# contas não paga a descoberta duas vezes. Vale por 90 dias; depois disso a pesquisa consulta de novo.
#
# `qsa` guarda o quadro de sócios sem menor de idade e, da pessoa física, só nome, qualificação e data de entrada
# (Research::PersonFields::ALLOWED). `owners` é a escolha da regra do dono para o tipo de decisor pedido (data['requested_role']).
# Tabela nova: nada existente muda.
class CreateAutonomiaProspectingCompanyProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :autonomia_prospecting_company_profiles do |t|
      t.string :cnpj, null: false, limit: 14
      t.string :legal_name
      t.string :trade_name
      t.string :registration_status
      t.string :registration_state
      t.string :legal_nature_code
      t.string :legal_nature_text
      t.jsonb :data, null: false, default: {}
      t.jsonb :qsa, null: false, default: []
      t.jsonb :owners, null: false, default: []
      t.jsonb :sources, null: false, default: []
      t.datetime :verified_at, null: false
      t.timestamps
    end

    add_index :autonomia_prospecting_company_profiles, :cnpj, unique: true
  end
end
