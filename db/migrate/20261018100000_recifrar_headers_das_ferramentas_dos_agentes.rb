# Dados (#1301): cifra os cabeçalhos das Ferramentas dos agentes que foram gravados antes das chaves.
#
# `Autonomia::Agents::Tool` declara `encrypts :headers_config` quando as chaves existem, mas linha gravada antes
# continua em claro: com `support_unencrypted_data` ela é lida normalmente e nunca é recifrada sozinha. Aqui cada
# linha em claro passa por `encrypt` (Rails 7.2: monta os atributos cifráveis e grava com `update_columns`, sem
# callbacks, validações nem `updated_at`). O valor lido continua o mesmo; só o que fica no banco muda.
#
# Sem chaves, não faz nada. Linha já cifrada não é tocada, então rodar de novo não muda nada.
#
# Model próprio, e não o do app: o `encrypts` do app depende de `Chatwoot.encryption_configured?` na hora em que a
# classe carrega, e aqui a decisão é tomada no `up`. A declaração é a mesma (`encrypts` sem opções; o resto vem da
# configuração global em config/application.rb).
#
# O log leva só ids e contagem, nunca valor de cabeçalho.
class RecifrarHeadersDasFerramentasDosAgentes < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  Ferramenta = Class.new(ActiveRecord::Base) do
    self.table_name = 'autonomia_agent_tools'

    encrypts :headers_config
  end

  def up
    return say('chaves de criptografia ausentes: nada a cifrar') unless Chatwoot.encryption_configured?

    Ferramenta.reset_column_information
    ids = cifrar_linhas_em_claro
    Rails.logger.info "[recifrar_headers] cifradas=#{ids.size} ids=#{ids.inspect}"
    say "ferramentas cifradas: #{ids.size}"
  end

  # Sem volta, de propósito: decifrar devolveria segredo de cliente ao banco em claro.
  def down; end

  private

  def cifrar_linhas_em_claro
    Ferramenta.find_each.filter_map do |ferramenta|
      next unless em_claro?(ferramenta)

      ferramenta.encrypt
      ferramenta.id
    end
  end

  def em_claro?(ferramenta)
    bruto = ferramenta.read_attribute_before_type_cast(:headers_config)
    return false if bruto.blank?

    !ActiveRecord::Encryption.encryptor.encrypted?(bruto)
  end
end
