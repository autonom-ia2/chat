# #2931 e #2936 (épico #2414, frente B): dois índices parciais pequenos para as duas leituras novas dos passos que
# esperam resposta, achados na revisão independente.
#
# - Os pedidos de aprovação de uma pessoa (PedidosDeAprovacao.da_pessoa: a tela "Pedidos de aprovação" e o sino). Sem
#   índice, cada abertura lia todos os registros da conta nos 30 dias de retenção, e todo passo de toda automação grava
#   registro. O índice guarda só os registros de espera (`motivo = 'esperando_resposta'`), por conta e data (a ordem da
#   tela).
# - O resumo da pesquisa na lista de automações (ResumoDaPesquisa). Sem índice, cada carga da lista com uma pesquisa
#   varria todos os contatos da conta. O índice guarda só os contatos que já responderam alguma pesquisa (o mesmo
#   filtro da consulta: `additional_attributes.pesquisas` é um objeto).
#
# Por que migration: as duas consultas filtram por um valor que nenhum índice existente cobre, e a alternativa (um
# contador gravado pelo passo) duplicaria a nota em mais um lugar. Aditiva: só índices novos, nenhuma coluna, nenhum
# dado mexido.
#
# CONCURRENTLY e fora de transação: não trava escrita em `contacts` nem nos registros. O índice que já existe e é
# válido fica; o inválido (CREATE INDEX CONCURRENTLY que caiu no meio) é apagado e refeito, porque o IF NOT EXISTS o
# daria por pronto só pelo nome; depois de criado, é conferido válido. Só durante cada CREATE/DROP o lock_timeout sobe
# para 15 min e o statement_timeout fica zerado (como no #2211 e no G50); os dois voltam no ensure.
#
# Os textos dos filtros ficam aqui, e não nas constantes do app: a migration não muda quando o código muda.
class AddIndicesDosPassosQueEsperam < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICES = [
    { tabela: :autonomia_automacao_registros, colunas: %i[account_id created_at], nome: 'idx_autonomia_automacao_registros_esperando',
      onde: "motivo = 'esperando_resposta'" },
    { tabela: :contacts, colunas: %i[account_id], nome: 'idx_contacts_com_pesquisa',
      onde: "jsonb_typeof(additional_attributes -> 'pesquisas') = 'object'" }
  ].freeze

  def up
    INDICES.each { |indice| criar_valido(**indice) }
  end

  def down
    INDICES.each do |indice|
      com_espera_longa { remove_index indice[:tabela], name: indice[:nome], algorithm: :concurrently, if_exists: true }
    end
  end

  private

  def criar_valido(tabela:, colunas:, nome:, onde:)
    return if valido?(nome) == true

    com_espera_longa do
      remove_index tabela, name: nome, algorithm: :concurrently if valido?(nome) == false
      add_index tabela, colunas, where: onde, name: nome, algorithm: :concurrently
    end
    raise "#2414: o índice #{nome} foi criado, mas ficou inválido" unless valido?(nome) == true
  end

  def com_espera_longa
    anteriores = { 'lock_timeout' => select_value('SHOW lock_timeout'), 'statement_timeout' => select_value('SHOW statement_timeout') }
    safety_assured { execute "SET lock_timeout = '15min'; SET statement_timeout = 0" }
    yield
  ensure
    anteriores&.each { |nome, valor| safety_assured { execute "SET #{nome} = #{connection.quote(valor)}" } }
  end

  # true = existe e é válido; false = existe e é inválido; nil = não existe.
  def valido?(nome)
    select_value("SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = #{connection.quote(nome)}")
  end
end
