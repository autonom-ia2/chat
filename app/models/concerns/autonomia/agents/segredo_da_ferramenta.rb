# A chave de acesso guardada (cabeçalho marcado como segredo) e a senha que alguém tente pôr no link. Com a chave
# delegada (#1430), quem mexe na ferramenta pode não ser quem cadastrou a chave.
module Autonomia::Agents::SegredoDaFerramenta
  extend ActiveSupport::Concern

  included do
    validate :validate_chave_mascarada
    validate :validate_chave_no_mesmo_destino, on: :update
    validate :validate_senha_fora_do_link
  end

  private

  # Revisão adversarial e decisão do Rodrigo (09/11): a chave guardada não vai para outro site nem para outro caminho,
  # busca ou método do mesmo site (trocar /leads por /persons usaria a chave do administrador em outra parte da API).
  # Mudou o link ou o método, a chave é digitada de novo.
  def validate_chave_no_mesmo_destino
    return unless will_save_change_to_endpoint_url? || will_save_change_to_http_method?
    return unless chave_guardada_reaproveitada?

    errors.add(:headers_config, I18n.t('autonomia.agents.ferramenta.chave_de_novo_destino'))
  end

  def chave_guardada_reaproveitada?
    guardadas = Array(headers_config_in_database).select { |header| header['secret'] }.map { |header| header.values_at('key', 'value') }
    headers_config.any? { |header| header['secret'] && guardadas.include?(header.values_at('key', 'value')) }
  end

  # A máscara voltou sem chave guardada com o mesmo nome (renomeou, ou desligou o segredo): seria gravada como a chave.
  def validate_chave_mascarada
    mascarada = headers_config.any? { |header| header['value'] == self.class.masked_header_value }
    errors.add(:headers_config, I18n.t('autonomia.agents.ferramenta.chave_de_novo')) if mascarada
  end

  # Decisão do Rodrigo (09/11): senha no link (usuário:senha@ ou ?token=) fica legível para quem tem a chave. O lugar dela
  # é a Chave de acesso, que ninguém relê. Lido pelo parser de URI, com o que o agente preenche ({{ }}) tirado antes:
  # `?token={{t}}` vem da conversa e vale.
  def validate_senha_fora_do_link
    errors.add(:endpoint_url, I18n.t('autonomia.agents.ferramenta.senha_no_link')) if senha_no_link?
  end

  def senha_no_link?
    uri = URI.parse(sem_modelo(endpoint_url.to_s))
    uri.userinfo.present? || credencial_na_busca?(uri.query)
  rescue URI::InvalidURIError, ArgumentError
    false
  end

  def credencial_na_busca?(busca)
    URI.decode_www_form(busca.to_s).any? do |nome, valor|
      valor.present? && Autonomia::Agents::Tools::SegredosDaChamada::NOMES_DE_CREDENCIAL.any? { |credencial| credencial.casecmp?(nome) }
    end
  end
end
