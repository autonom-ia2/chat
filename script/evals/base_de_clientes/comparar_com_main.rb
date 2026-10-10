# Prova de liberação da flag customer_base (#1246): roda a importação de contatos de verdade
# (ContactImports::Validator, com banco, anexo e linhas gravadas) sobre uma pasta de planilhas e
# grava, por planilha, tudo o que ela produz. Rodado no main e na branch com a flag desligada, os
# dois arquivos têm de ser idênticos.
#
# O Jev varia de uma chamada para outra; para a diferença só poder vir do código, as respostas são
# gravadas na primeira rodada e reproduzidas nas seguintes. Uma pergunta que não está na gravação
# quer dizer que o pedido ao Jev mudou: com JEV_SO_REPRODUZIR=1 isso para a rodada.
#
# Só em banco de teste, nunca em produção:
#   RAILS_ENV=test PLANILHAS=<pasta> SAIDA=<arquivo.json> JEV_GRAVACAO=<arquivo.json> [CUSTOMER_BASE=1]
#   [JEV_SO_REPRODUZIR=1] TYPESAFE_API_KEY=... bundle exec rails runner script/evals/base_de_clientes/comparar_com_main.rb
abort 'Só em RAILS_ENV=test.' unless Rails.env.test?
# DATABASE_URL entra em qualquer ambiente do Rails: confere o banco de fato conectado.
abort "Banco #{ActiveRecord::Base.connection.current_database} não é de teste." unless
  ActiveRecord::Base.connection.current_database.start_with?('chatwoot_test')

module CompararComMain
  PerguntaNova = Class.new(StandardError)

  # Grava e reproduz as respostas do Jev pela pergunta inteira (estado, perguntas e modelo).
  module JevGravado
    def evaluate(state:, questions:, model: TypesafeAi::Config.model)
      chave = Digest::SHA256.hexdigest(JSON.generate({ state: state, questions: questions, model: model }))
      gravacao = CompararComMain.gravacao
      return gravacao.fetch(chave) if gravacao.key?(chave)
      raise PerguntaNova, chave if ENV['JEV_SO_REPRODUZIR'] == '1'

      gravacao[chave] = super
    end
  end

  def self.gravacao
    @gravacao ||= File.exist?(ENV.fetch('JEV_GRAVACAO')) ? JSON.parse(File.read(ENV.fetch('JEV_GRAVACAO'))) : {}
  end

  def self.salvar_gravacao
    File.write(ENV.fetch('JEV_GRAVACAO'), JSON.pretty_generate(gravacao))
  end
end

TypesafeAi::Client.prepend(CompararComMain::JevGravado)
TypesafeAi::Config.define_singleton_method(:api_key) { ENV.fetch('TYPESAFE_API_KEY') }
CampaignImports::JevConfig.define_singleton_method(:available?) { true }

# Só máscaras e hashes saem no arquivo: o nome vira hash, e os CSVs também, o que basta para provar igualdade.
LINHA = %w[row_number status error_messages raw_phone_masked email_masked normalized_phone_hash normalized_email_hash].freeze
RESOLUCAO = %w[method needs_confirmation header_row table_index uncertain_targets].freeze
TIPOS = { '.csv' => 'text/csv', '.xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }.freeze

account = Account.create!(name: "Comparação #{SecureRandom.hex(4)}")
account.enable_features!('customer_base') if ENV['CUSTOMER_BASE'] == '1'
user = User.create!(name: 'Comparação', email: "comparacao-#{SecureRandom.hex(4)}@example.com", password: 'Passw0rd!23',
                    confirmed_at: Time.current)
AccountUser.create!(account: account, user: user, role: :administrator)

def importar(account, user, caminho)
  nome = File.basename(caminho)
  conteudo = File.binread(caminho)
  campaign_import = account.campaign_imports.create!(
    user: user, status: :uploaded, mode: 'single_label', batch_count: 1,
    options: { default_country: 'BR', flow: CampaignImport::CONTACTS_FLOW, create_companies: true },
    source_filename: nome, source_content_type: TIPOS.fetch(File.extname(nome)), source_byte_size: conteudo.bytesize,
    source_format: File.extname(nome).delete('.')
  )
  campaign_import.original_file.attach(io: StringIO.new(conteudo), filename: nome, content_type: TIPOS.fetch(File.extname(nome)))
  campaign_import
end

# Como a pessoa que aceita as colunas sugeridas: assim as linhas também passam pela comparação.
def aceitar_sugestao(campaign_import)
  sugeridas = campaign_import.schema_resolution['targets'].to_h.transform_values { |alvo| alvo['column'] }
  return false if sugeridas.values_at('phone', 'email').all?(&:nil?)

  campaign_import.update!(schema_resolution: campaign_import.schema_resolution.merge('manual_mapping' => sugeridas))
  ContactImports::Validator.new(campaign_import).perform
  true
end

def retrato(campaign_import, aceitou)
  campaign_import.reload
  {
    status: campaign_import.status, aceitou_sugestao: aceitou,
    total: campaign_import.total_rows, validas: campaign_import.valid_rows, invalidas: campaign_import.invalid_rows,
    resolucao: resolucao(campaign_import.schema_resolution.to_h), resumo: campaign_import.validation_summary.to_h.except('validated_at'),
    linhas: campaign_import.campaign_import_rows.order(:row_number).map { |linha| linha_mascarada(linha) },
    csv_normalizado: texto(campaign_import.normalized_csv), csv_de_erros: texto(campaign_import.error_csv)
  }
end

def resolucao(resolucao)
  resolucao.slice(*RESOLUCAO).merge('colunas' => resolucao['targets'].to_h.transform_values { |alvo| alvo['column'] })
end

def texto(anexo)
  anexo.attached? ? Digest::SHA256.hexdigest(anexo.download) : nil
end

def linha_mascarada(linha)
  dados = %w[raw_name company_name extra_values].index_with { |campo| Digest::SHA256.hexdigest(linha[campo].to_json) }
  linha.attributes.slice(*LINHA).merge(dados)
end

planilhas = Dir.children(ENV.fetch('PLANILHAS')).select { |nome| TIPOS.key?(File.extname(nome)) }.sort
resultado = planilhas.map { |nome| File.join(ENV.fetch('PLANILHAS'), nome) }.to_h do |caminho|
  campaign_import = importar(account, user, caminho)
  ContactImports::Validator.new(campaign_import).perform
  aceitou = campaign_import.reload.needs_column_choice? && aceitar_sugestao(campaign_import)
  [File.basename(caminho), retrato(campaign_import, aceitou)]
ensure
  CompararComMain.salvar_gravacao
end

File.write(ENV.fetch('SAIDA'), JSON.pretty_generate(resultado))
puts "#{resultado.size} planilhas → #{ENV.fetch('SAIDA')}"
