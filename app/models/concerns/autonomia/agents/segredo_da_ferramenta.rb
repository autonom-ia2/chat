# A chave de acesso guardada (cabeçalho marcado como segredo) e a senha que alguém tente pôr no link. Com a chave
# delegada (#1430), quem mexe na ferramenta pode não ser quem cadastrou a chave.
module Autonomia::Agents::SegredoDaFerramenta
  extend ActiveSupport::Concern

  # `chaves_digitadas`: os nomes dos cabeçalhos de segredo que chegaram digitados agora (sem a máscara), marcados pelo
  # controller. A mesma chave digitada de novo vale para um pedido novo; sem a marca, o par igual ao guardado é a chave
  # reaproveitada. O nome basta porque o cadastro não aceita nome repetido (`CabecalhosDaFerramenta`).
  included do
    attr_accessor :chaves_digitadas

    validate :validate_chave_mascarada
    validate :validate_chave_no_mesmo_pedido, on: :update
    validate :validate_segredo_preenchido, if: -> { new_record? || will_save_change_to_headers_config? }
    validate :validate_senha_fora_do_link, if: -> { new_record? || will_save_change_to_endpoint_url? }
  end

  private

  # Revisão adversarial e decisão do Rodrigo (09/11): a chave guardada não vai para outro site nem para outra parte da
  # mesma API. Mudou o pedido (link, método, o que vai junto ou qualquer cabeçalho: um novo, um tirado, o valor de um
  # comum, ligar ou desligar o segredo — X-HTTP-Method-Override troca o método sem mexer no método), a chave é digitada
  # de novo. Trocar só o valor de uma chave não muda o pedido.
  def validate_chave_no_mesmo_pedido
    return unless pedido_mudou?

    errors.add(:headers_config, I18n.t('autonomia.agents.ferramenta.chave_de_novo_destino')) if chave_guardada_reaproveitada?
  end

  # Segredo vazio apagaria a chave guardada em silêncio.
  def validate_segredo_preenchido
    errors.add(:headers_config, I18n.t('autonomia.agents.ferramenta.chave_vazia')) if segredo_vazio?
  end

  def pedido_mudou?
    will_save_change_to_endpoint_url? || will_save_change_to_http_method? ||
      attribute_in_database(:request_body_template).to_s != request_body_template.to_s ||
      cabecalhos_do_pedido(headers_config) != cabecalhos_do_pedido(headers_config_in_database)
  end

  def chave_guardada_reaproveitada?
    guardadas = cabecalhos_de(headers_config_in_database).select { |header| segredo?(header) }.map { |header| header.values_at('key', 'value') }
    digitadas = Array(chaves_digitadas)
    cabecalhos_de(headers_config).any? do |header|
      segredo?(header) && guardadas.include?(header.values_at('key', 'value')) && digitadas.exclude?(header['key'])
    end
  end

  def segredo_vazio?
    cabecalhos_de(headers_config).any? { |header| segredo?(header) && header['value'].to_s.strip.empty? }
  end

  # O pedido pelos cabeçalhos: o segredo conta pelo nome, o comum pelo nome e pelo valor.
  def cabecalhos_do_pedido(lista)
    cabecalhos_de(lista).map do |header|
      segredo = segredo?(header)
      [header['key'].to_s.strip.downcase, segredo ? 1 : 0, segredo ? '' : header['value'].to_s]
    end.sort
  end

  def cabecalhos_de(lista)
    Array(lista).map { |header| header.to_h.stringify_keys }
  end

  def segredo?(header)
    ActiveModel::Type::Boolean.new.cast(header['secret'])
  end

  # A máscara voltou sem chave guardada com o mesmo nome (renomeou, ou desligou o segredo): seria gravada como a chave.
  def validate_chave_mascarada
    mascarada = cabecalhos_de(headers_config).any? { |header| header['value'] == self.class.masked_header_value }
    errors.add(:headers_config, I18n.t('autonomia.agents.ferramenta.chave_de_novo')) if mascarada
  end

  # Decisão do Rodrigo (09/11): senha no link (usuário:senha@ ou ?token=) fica legível para quem tem a chave. O lugar dela
  # é a Chave de acesso, que ninguém relê. Conferida no cadastro e quando o link muda: a ferramenta antiga continua podendo
  # ser desligada. O usuário sai do parser de URI; a busca é lida crua, com `;` também separando, e o nome sem `[]`
  # (`token[]` é `token` para Rails e PHP). Vale o valor que só tem informação da conversa (`{{t}}`).
  def validate_senha_fora_do_link
    errors.add(:endpoint_url, I18n.t('autonomia.agents.ferramenta.senha_no_link')) if senha_no_link?
  end

  def senha_no_link?
    URI.parse(sem_modelo(endpoint_url.to_s)).userinfo.present? || credencial_na_busca?
  rescue URI::InvalidURIError
    false # o endereço inválido já é recusado por `validate_endpoint_url`
  rescue ArgumentError
    true # busca que nem o parser lê não passa como sem senha
  end

  def credencial_na_busca?
    busca = endpoint_url.to_s.split('#', 2).first.to_s.split('?', 2).second.to_s.tr(';', '&')
    URI.decode_www_form(busca).any? do |nome, valor|
      Autonomia::Agents::Tools::SegredosDaChamada.credencial?(nome_fixo(nome)) && valor_fixo(valor).strip.present?
    end
  end

  # O que sobra do valor sem as informações da conversa: `{{t}}` e `{{ t | url_encode }}` saem; `{{ "abc" }}` e
  # `{{ t | append: "x" }}` levam texto fixo e ficam.
  def valor_fixo(valor)
    partes = valor.to_s.split('{{', -1)
    partes.drop(1).reduce(partes.first.to_s) do |saida, pedaco|
      dentro, depois = pedaco.split('}}', 2)
      next "#{saida}{{#{pedaco}" if depois.nil?

      "#{saida}#{so_informacao?(dentro) ? '' : dentro}#{depois}"
    end
  end

  # `?{{ "token" }}=abc` vira `token=abc` na chamada.
  def nome_fixo(nome)
    valor_fixo(nome).delete(%('")).strip
  end

  def so_informacao?(dentro)
    nome, *filtros = dentro.split('|').map(&:strip)
    nome.present? && !nome.start_with?('"', "'") && !('0'..'9').cover?(nome[0]) && filtros.all?('url_encode')
  end
end
