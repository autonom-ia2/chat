# Dados (#1344): cifra os segredos gravados antes de a stack ter as chaves de criptografia.
#
# As colunas abaixo são declaradas com `encrypts ... if Chatwoot.encryption_configured?`. Linha gravada antes das
# chaves continua em claro: com `support_unencrypted_data` ela é lida normalmente e nunca é recifrada sozinha, porque
# o Rails só cifra o atributo quando ele muda. Em 12/10/2026 eram 27 linhas no Hub2You e 15 na Autonom.ia.
#
# Cada linha com alguma dessas colunas em claro passa por `encrypt` (Rails 7.2: grava os atributos cifráveis com
# `update_columns`, sem callbacks, validações nem `updated_at`). O valor lido continua o mesmo; só o que fica no banco
# muda. As determinísticas seguem achadas por `find_by`: o valor buscado é cifrado do mesmo jeito.
#
# Sem chaves, não faz nada. Linha sem nada em claro não é tocada, então rodar de novo não muda nada. Numa linha
# mista, `encrypt` regrava também as colunas que já estavam cifradas, com o mesmo valor.
#
# Models próprios, e não os do app: o `encrypts` do app depende de `Chatwoot.encryption_configured?` na hora em que a
# classe carrega, e aqui a decisão é tomada no `up`. As declarações são as mesmas do app (só `deterministic` muda o
# modo; o resto vem da configuração global em config/application.rb).
#
# Fora daqui: `autonomia_agent_tools.headers_config` (#1328) e as colunas que o app cifra sem condição — essas recusam
# gravar sem chaves e estavam 100% cifradas nas duas stacks.
#
# O log leva só contagem por coluna, nunca valor nem id.
class RecifrarSegredosLegados < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  COLUNAS = {
    'account_email_oauth_apps' => %i[client_secret],
    'agent_bots' => %i[secret],
    'autonomia_prospecting_settings' => %i[google_places_api_key google_maps_browser_api_key],
    'channel_api' => %i[secret],
    'channel_email' => %i[imap_password smtp_password],
    'channel_facebook_pages' => %i[page_access_token user_access_token],
    'channel_instagram' => %i[access_token],
    'channel_line' => %i[line_channel_secret line_channel_token],
    'channel_telegram' => %i[bot_token],
    'channel_tiktok' => %i[access_token refresh_token],
    'channel_twilio_sms' => %i[auth_token api_key_secret],
    'channel_twitter_profiles' => %i[twitter_access_token twitter_access_token_secret],
    'channel_whatsapp' => %i[business_management_token],
    'crm_meta_ads_connections' => %i[whatsapp_report_phone],
    'data_imports' => %i[access_token],
    'integrations_hooks' => %i[access_token],
    'webhooks' => %i[secret],
    'whatsapp_hybrid_connections' => %i[webhook_secret]
  }.freeze

  # As que o app declara com `deterministic: true`: o mesmo valor gera o mesmo texto cifrado, para a busca por igualdade.
  DETERMINISTICAS = {
    'channel_telegram' => %i[bot_token],
    'integrations_hooks' => %i[access_token]
  }.freeze

  def up
    return say('chaves de criptografia ausentes: nada a cifrar') unless Chatwoot.encryption_configured?

    contagem = COLUNAS.flat_map { |tabela, colunas| cifrar_tabela(tabela, colunas) }.to_h
    Rails.logger.info "[recifrar_segredos] #{contagem.map { |coluna, total| "#{coluna}=#{total}" }.join(' ')}"
    say "segredos cifrados: #{contagem.values.sum}"
  end

  # Sem volta, de propósito: decifrar devolveria segredo de cliente ao banco em claro. A imagem anterior lê as linhas
  # cifradas aqui com as mesmas chaves, então voltar a imagem não exige voltar os dados.
  def down; end

  def self.modelo(tabela, colunas)
    deterministicas = DETERMINISTICAS.fetch(tabela, [])

    Class.new(ActiveRecord::Base) do
      self.table_name = tabela
      self.inheritance_column = :_sem_heranca

      colunas.each { |coluna| encrypts coluna, deterministic: deterministicas.include?(coluna) }
    end
  end

  private

  # Devolve [["tabela.coluna", total]] para cada coluna, inclusive as que ficaram em zero.
  def cifrar_tabela(tabela, colunas)
    totais = colunas.index_with(0)
    model = self.class.modelo(tabela, colunas)

    model.find_each do |registro|
      em_claro = colunas.select { |coluna| em_claro?(registro, coluna) }
      next if em_claro.empty?

      registro.encrypt
      em_claro.each { |coluna| totais[coluna] += 1 }
    end

    totais.map { |coluna, total| ["#{tabela}.#{coluna}", total] }
  end

  def em_claro?(registro, coluna)
    bruto = registro.read_attribute_before_type_cast(coluna)
    return false if bruto.blank?

    !ActiveRecord::Encryption.encryptor.encrypted?(bruto)
  end
end
