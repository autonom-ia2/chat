# UMA EMPRESA POR CNPJ EM CADA CONTA (chat#680, E4 frente A), criado sem travar a escrita na tabela de empresas.
#
# A prospecção grava o CNPJ em additional_attributes['cnpj'] (14 dígitos). Dois leads da mesma empresa enviados ao
# mesmo tempo caem aqui no RecordNotUnique e o segundo reaproveita a empresa do primeiro. Empresa sem CNPJ não entra.
class AddCnpjIndexToCompanies < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :companies, "account_id, (additional_attributes ->> 'cnpj')",
              unique: true, algorithm: :concurrently, name: 'index_companies_on_account_and_cnpj',
              where: "(additional_attributes ->> 'cnpj') IS NOT NULL"
  end
end
