# Épico #1240, decisão R1 (13/11/2026): o CPF da pessoa e o CNPJ da empresa em tabela própria do fork, com o valor cifrado
# e busca por valor exato. Só aditiva: uma tabela nova, que nada lê nem grava ainda (as etapas E6.3, E7.2 e E8.3 do
# épico passam a usar; o CPF que hoje é atributo personalizado e o CNPJ de `companies.additional_attributes` seguem
# onde estão, e trazê-los para cá é uma entrega própria).
#
# - `valor`: o número na forma de comparação (só dígitos; o CNPJ no formato novo, com letras, em maiúscula). O model cifra com a
#   cifra determinística do Rails quando a instalação tem as chaves (`encrypts ..., deterministic: true`): o mesmo
#   número vira sempre o mesmo texto cifrado, então o índice de busca serve do mesmo jeito. Sem as chaves o valor fica em
#   texto puro, como nas outras colunas cifradas do fork. Sem limite de tamanho: o texto cifrado é bem maior que o número.
# - dono: a pessoa (`contact_id`) OU a empresa (`company_id`), nunca as duas nem nenhuma (CHECK `_dono`). São duas
#   colunas com chave estrangeira, e não um par tipo/id polimórfico, para o banco apagar o documento junto com o dono:
#   há caminho que apaga contato sem callback (`Internal::RemoveStaleContactsService`, a exclusão da conta), e
#   documento órfão é dado pessoal sem dono.
# - tipo e dono: a pessoa pode ter CPF e CNPJ (o MEI é pessoa com CNPJ); a empresa só tem CNPJ (CHECK
#   `_cpf_so_de_pessoa`). Decidido com a tabela ainda vazia, para o banco nunca guardar CPF como dado de empresa.
#
# Chaves:
# - account: sem cascata, como as outras tabelas do fork; a exclusão da conta (Autonomia::ExclusaoDaConta) apaga os
#   documentos antes do DELETE da conta;
# - contact e company: em cascata. O documento não tem arquivo nem história: sai com a pessoa ou com a empresa.
#
# Índices:
# - único [contact_id, tipo] e único [company_id, tipo], parciais: um documento de cada tipo por dono. Começam pela coluna da
#   chave, então também servem ao gatilho da cascata quando o contato ou a empresa é apagado;
# - [account_id, tipo, valor]: a busca por valor exato dentro da conta, e a chave da conta. NÃO é único de propósito: a
#   base real tem a mesma pessoa cadastrada duas vezes, e recusar o segundo documento travaria a importação. Quem casa
#   pessoa por documento recebe todos os donos e decide.
#
# Tipo é texto com CHECK, o padrão do fork.
#
# Travas: um CREATE TABLE só, que pega SHARE ROW EXCLUSIVE em accounts, contacts e companies pelo instante do comando,
# sem varrer linha (a tabela nasce vazia), com o lock_timeout curto do strong_migrations. O down remove a tabela.
class CreateRelacionamentosDocumentos < ActiveRecord::Migration[7.2]
  TIPOS = "tipo::text = ANY ('{cpf,cnpj}'::text[])".freeze
  DONO = 'num_nonnulls(contact_id, company_id) = 1'.freeze
  CPF_SO_DE_PESSOA = "tipo::text = 'cnpj'::text OR contact_id IS NOT NULL".freeze

  def change
    create_table :relacionamentos_documentos do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :contact, foreign_key: { on_delete: :cascade }, index: false
      t.references :company, foreign_key: { on_delete: :cascade }, index: false
      t.string :tipo, null: false
      t.string :valor, null: false
      t.timestamps
      t.index %i[account_id tipo valor], name: 'idx_relacionamentos_documentos_busca'
      t.index %i[contact_id tipo], unique: true, where: 'contact_id IS NOT NULL', name: 'idx_relacionamentos_documentos_da_pessoa'
      t.index %i[company_id tipo], unique: true, where: 'company_id IS NOT NULL', name: 'idx_relacionamentos_documentos_da_empresa'
      t.check_constraint TIPOS, name: 'relacionamentos_documentos_tipo'
      t.check_constraint DONO, name: 'relacionamentos_documentos_dono'
      t.check_constraint CPF_SO_DE_PESSOA, name: 'relacionamentos_documentos_cpf_so_de_pessoa'
    end
  end
end
