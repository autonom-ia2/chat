# Os endereços que o botão de link pode levar (#1479): só os que o DONO autorizou (`do_dono`), inteiros.
#
# Cada palavra do texto (separada por espaço) que contém "http" (sem diferenciar caixa) vira candidata a partir dali,
# sem a pontuação colada no fim (o ponto final da frase, o parêntese do markdown); quem decide se é endereço é o
# Addressable: http ou https, com host. Sem regex. O pedido do modelo vale só se for IGUAL a um deles depois de
# normalizar (esquema e host em minúsculas, o resto igual): pedaço de endereço, ou endereço a mais, nunca vale.
module Autonomia::Agents::Interacao::Enderecos
  ESQUEMAS = %w[http https].freeze
  PONTUACAO_DO_FIM = ['.', ',', ';', ':', '!', '?', ')', ']', '}', '>', '"', "'", '*', '_'].freeze

  module_function

  # -> Set dos endereços que o botão pode levar neste turno (regra final da revisão adversarial):
  #   - os que estão em `dono` (a instrução do agente e a base de conhecimento);
  #   - os `url` dos botões de link que o agente já mandou nesta `conversation` (já passaram por esta conferência);
  #   - os das saídas de `ferramentas` (HTTP, sistema) só quando o HOST deles já aparece num endereço de `dono`: o dono
  #     autoriza o domínio, a ferramenta traz o caminho.
  # Fala do agente em texto, saída de especialista ou ajudante, fala do cliente e memória não entram.
  def do_dono(dono:, ferramentas:, conversation:)
    do_dono = dos_textos(dono)
    hosts = do_dono.to_set { |endereco| host(endereco) }
    das_ferramentas = dos_textos(ferramentas).select { |endereco| hosts.include?(host(endereco)) }
    do_dono | das_ferramentas | dos_botoes(conversation)
  end

  # Os `url` dos botões de link que o agente já mandou na conversa, normalizados.
  def dos_botoes(conversation)
    return Set.new if conversation.nil?

    conversation.messages.outgoing.where(sender_type: 'AgentBot').where('content_attributes::text LIKE ?', '%link_button%')
                .filter_map { |message| url_do_botao(message.content_attributes.to_h) }.to_set
  end

  def url_do_botao(atributos)
    formato = atributos['rich_message']
    return unless atributos['autonomia_agent_id'].present? && formato.is_a?(Hash) && formato['type'] == 'link_button'

    normalizado(formato['url'])
  end

  def host(endereco)
    Addressable::URI.parse(endereco).host
  end

  # -> Set dos endereços normalizados que aparecem nos textos.
  def dos_textos(textos)
    textos.compact.flat_map { |texto| texto.to_s.split }.filter_map { |palavra| candidato(palavra) }.to_set
  end

  # -> o endereço normalizado, ou nil quando não é http(s) com host.
  def normalizado(endereco)
    return unless endereco.is_a?(String)

    uri = Addressable::URI.parse(endereco)
    return unless ESQUEMAS.include?(uri.scheme.to_s.downcase) && uri.host.present?

    uri.scheme = uri.scheme.downcase
    uri.host = uri.host.downcase
    uri.to_s
  rescue Addressable::URI::InvalidURIError
    nil
  end

  def candidato(palavra)
    inicio = palavra.downcase(:ascii).index('http') # só ASCII: as posições não mudam
    return if inicio.nil?

    endereco = palavra[inicio..]
    endereco = endereco[0...-1] while PONTUACAO_DO_FIM.any? { |sinal| endereco.end_with?(sinal) }
    normalizado(endereco)
  end
end
