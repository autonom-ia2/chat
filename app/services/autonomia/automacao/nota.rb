# Nota privada da Automação na conversa, mencionando quem deve ver (#2414 F4). A menção é o aviso que a plataforma já
# tem (Messages::MentionService): sino, push e e-mail pela preferência de cada pessoa, abrindo a conversa. O cliente
# nunca vê. Sai sem remetente e com a marca da automação, como a mensagem.
class Autonomia::Automacao::Nota
  def self.criar(conversa:, texto:, pessoas:, marca:)
    mencoes = pessoas.map { |pessoa| "[@#{pessoa.name}](mention://user/#{pessoa.id}/#{ERB::Util.url_encode(pessoa.name)})" }
    conteudo = [texto, mencoes.join(' ').presence].compact.join("\n\n")
    ::Messages::MessageBuilder.new(nil, conversa, content: conteudo, private: true, content_attributes: marca).perform
  end

  # Só quem enxerga a conversa (D5): a mesma política que o endpoint usaria para essa pessoa.
  def self.alcancaveis(conversa, ids)
    conversa.account.users.where(id: ids.compact.uniq).select do |pessoa|
      ::Autonomia::Automacao::Acesso.alcanca?(pessoa, conversa)
    end
  end
end
