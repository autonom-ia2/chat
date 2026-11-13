# #2896 (fatia 3): uma lista trazida grande, montada direto no banco (insert_all), para medir o que o "Desfazer" lê.
# Passar pela leitura e pela gravação de verdade levaria minutos; aqui só importa o que elas deixam gravado: as pessoas,
# as linhas da importação e os campos anotados. Todos os dados são inventados.
module ListaTrazidaGrandeHelpers
  LOTE = 5_000
  CLIENTE_DESDE = Time.utc(2026, 1, 15, 12)
  CIDADE = 'Campinas'.freeze
  # De cada tantas pessoas que a lista criou, uma recusou mensagens: é a que fica.
  UMA_RECUSA_A_CADA = 20
  Medida = Struct.new(:resultado, :consultas, :segundos, :por_tabela, keyword_init: true)

  # A lista já gravada, ainda sem linha nenhuma.
  def lista_trazida_vazia(conta, quem)
    conta.campaign_imports.create!(user: quem, status: :completed, mode: 'single_label',
                                   options: { 'flow' => CampaignImport::CONTACTS_FLOW, 'trazer' => {} })
  end

  # `quantas` pessoas que a lista criou, uma linha cada. Devolve quantas recusaram mensagens.
  def por_pessoas_criadas(importacao, quantas)
    em_lotes(importacao, quantas) do |numeros|
      pessoas = numeros.map { |numero| pessoa_criada(importacao.account_id, numero) }
      inserir_linhas(importacao, numeros, inserir(Contact, pessoas), ja_existia: false)
    end
    quantas / UMA_RECUSA_A_CADA
  end

  # `quantas` pessoas que a conta já tinha, uma linha cada, com três campos que a lista preencheu: e-mail, cidade e a
  # marca de cliente. Os três estão como a lista os deixou, então os três voltam.
  def por_pessoas_completadas(importacao, quantas)
    em_lotes(importacao, quantas) do |numeros|
      pessoas = numeros.map { |numero| pessoa_completada(importacao.account_id, numero) }
      ids = inserir(Contact, pessoas)
      linhas = inserir_linhas(importacao, numeros, ids, ja_existia: true)
      inserir(Relacionamentos::CampoPreenchido, campos_das_linhas(importacao.account_id, linhas, ids, pessoas))
    end
  end

  # As estatísticas que o banco de produção tem (o autovacuum as mantém): sem elas o plano é o de tabela vazia.
  def atualizar_estatisticas
    ActiveRecord::Base.connection.execute('ANALYZE contacts, campaign_import_rows, relacionamentos_campos_preenchidos')
  end

  # O bloco, com quantas consultas fez (fora as de esquema e de transação), o tempo de parede e, por tabela, quantas
  # consultas e quantos segundos.
  def medir_consultas
    por_tabela = Hash.new { |tabelas, nome| tabelas[nome] = { consultas: 0, segundos: 0.0 } }
    anotar = lambda do |_evento, inicio, fim, _id, dados|
      next if dados[:cached] || %w[SCHEMA TRANSACTION].include?(dados[:name])

      da_tabela = por_tabela[tabela_da_consulta(dados[:sql])]
      da_tabela[:consultas] += 1
      da_tabela[:segundos] += fim - inicio
    end
    resultado = nil
    segundos = Benchmark.realtime { ActiveSupport::Notifications.subscribed(anotar, 'sql.active_record') { resultado = yield } }
    Medida.new(resultado: resultado, consultas: por_tabela.values.sum { |da_tabela| da_tabela[:consultas] }, segundos: segundos,
               por_tabela: por_tabela)
  end

  private

  def em_lotes(importacao, quantas, &)
    primeiro = importacao.campaign_import_rows.maximum(:row_number).to_i + 1
    (primeiro...(primeiro + quantas)).each_slice(LOTE, &)
  end

  def pessoa_criada(conta_id, numero)
    carimbos.merge(account_id: conta_id, name: "Pessoa Criada #{numero}", phone_number: format('+5511%09d', 900_000_000 + numero),
                   opted_out_at: (Time.current if (numero % UMA_RECUSA_A_CADA).zero?))
  end

  def pessoa_completada(conta_id, numero)
    carimbos.merge(account_id: conta_id, name: "Pessoa Antiga #{numero}", email: "pessoa.antiga.#{numero}@exemplo.com.br",
                   additional_attributes: { 'city' => CIDADE }, contact_type: Contact.contact_types[:customer], customer_since: CLIENTE_DESDE)
  end

  def inserir_linhas(importacao, numeros, ids, ja_existia:)
    linhas = numeros.zip(ids).map do |numero, id|
      carimbos.merge(campaign_import_id: importacao.id, row_number: numero, contact_id: id, was_existing_contact: ja_existia,
                     status: CampaignImportRow.statuses[:imported])
    end
    inserir(CampaignImportRow, linhas)
  end

  def campos_das_linhas(conta_id, linhas, ids, pessoas)
    campo = Relacionamentos::CampoPreenchido
    linhas.zip(ids, pessoas).flat_map do |linha, id, pessoa|
      postos = { 'email' => pessoa[:email], campo::CIDADE => CIDADE, campo::CLIENTE => campo.instante(CLIENTE_DESDE) }
      postos.map do |nome, valor|
        carimbos.merge(account_id: conta_id, campaign_import_row_id: linha, contact_id: id, campo: nome,
                       valor_posto_hash: campo.resumo(linha, nome, valor), tipo_anterior: (Contact.contact_types[:lead] if nome == campo::CLIENTE))
      end
    end
  end

  # Devolve os ids, na ordem em que as linhas foram passadas.
  def inserir(modelo, linhas)
    modelo.insert_all!(linhas, returning: %w[id]).rows.flatten # rubocop:disable Rails/SkipsModelValidations -- dezenas de milhares de linhas
  end

  def carimbos
    agora = Time.current
    { created_at: agora, updated_at: agora }
  end

  # A tabela de onde a consulta lê: a primeira palavra depois de FROM, sem as aspas.
  def tabela_da_consulta(sql)
    sql.split(' FROM ', 2).last.to_s.split.first.to_s.delete('"')
  end
end

RSpec.configure do |config|
  config.include ListaTrazidaGrandeHelpers
end
