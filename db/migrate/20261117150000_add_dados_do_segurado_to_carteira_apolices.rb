# E8.1 (#3043): o que a cotação da renovação pede do segurado e a apólice traz escrito. Quem lê é o leitor de PDF e quem
# escreve à mão é a gaveta do seguro (Corrigir); a cotação usa o que estiver aqui.
# - `segurado_nascimento`: a data de nascimento do segurado pessoa, AAAA-MM-DD. É dado pessoal: o model a cifra (Active
#   Record Encryption, não determinística) quando a instalação tem as chaves. Por isso a coluna é texto e o CHECK de data
#   fica no model (o banco só vê o texto cifrado);
# - `segurado_sexo`: F ou M, como o portal de cotação lê;
# - `cep`: o CEP do endereço do segurado (ou do risco), 8 dígitos. O CHECK confere sem expressão regular: 8 caracteres
#   e nenhum que não seja dígito (o `translate` tira os dígitos e não pode sobrar nada);
# - `placa`: a placa na forma do portal (maiúsculas, sem traço nem espaço). A forma é conferida no model;
# - `bonus_classe`: a classe de bônus como está na apólice, de 0 a 10.
# Todas nulas, sem padrão: "não sei" é nulo, e o código anterior não conhece as colunas.
#
# Travas: cada ADD COLUMN pega ACCESS EXCLUSIVE só pelo instante (colunas nulas, sem reescrever a tabela). Os CHECKs
# entram NOT VALID (trava curta) e são validados depois, sem barrar escrita (strong_migrations); como as colunas acabaram
# de nascer nulas, a validação não acha linha ruim. As expressões já estão na forma que o Postgres devolve: a CI compara
# o dump com o schema.rb. Cada passo pode rodar de novo sem erro se o deploy cair no meio.
#
# Rollback: o `down` tira os CHECKs e as cinco colunas (nada mais depende delas).
class AddDadosDoSeguradoToCarteiraApolices < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  COLUNAS = [[:segurado_nascimento, :text], [:segurado_sexo, :string], [:cep, :string], [:placa, :string],
             [:bonus_classe, :integer, { limit: 2 }]].freeze
  CHECKS = {
    'carteira_apolices_sexo' => "segurado_sexo::text = ANY ('{F,M}'::text[])",
    'carteira_apolices_cep' => "length(cep::text) = 8 AND translate(cep::text, '0123456789'::text, ''::text) = ''::text",
    'carteira_apolices_bonus' => 'bonus_classe >= 0 AND bonus_classe <= 10'
  }.freeze

  def up
    COLUNAS.each { |coluna, tipo, opcoes| add_column :carteira_apolices, coluna, tipo, **opcoes.to_h, if_not_exists: true }
    CHECKS.each do |nome, expressao|
      add_check_constraint :carteira_apolices, expressao, name: nome, validate: false, if_not_exists: true
      validate_check_constraint :carteira_apolices, name: nome
    end
  end

  def down
    CHECKS.each_key { |nome| remove_check_constraint :carteira_apolices, name: nome, if_exists: true }
    COLUNAS.map(&:first).each { |coluna| remove_column :carteira_apolices, coluna, if_exists: true }
  end
end
