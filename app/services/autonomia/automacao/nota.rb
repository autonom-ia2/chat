# Nota privada da Automação na conversa, mencionando quem deve ver (#2414 F4). A menção é o aviso que a plataforma já
# tem (Messages::MentionService): sino, push e e-mail pela preferência de cada pessoa, abrindo a conversa. O cliente
# nunca vê. Sai sem remetente e com a marca da automação, como a mensagem.
class Autonomia::Automacao::Nota
  def self.criar(conversa:, texto:, pessoas:, marca:)
    mencoes = pessoas.map { |pessoa| "[@#{pessoa.name}](mention://user/#{pessoa.id}/#{ERB::Util.url_encode(pessoa.name)})" }
    conteudo = [texto, mencoes.join(' ').presence].compact.join("\n\n")
    ::Messages::MessageBuilder.new(nil, conversa, content: conteudo, private: true, content_attributes: marca).perform
  end

  # Só quem enxerga a conversa (D5), pela mesma política que o endpoint usaria para essa pessoa, e quem a menção avisa.
  def self.alcancaveis(conversa, ids)
    avisaveis = avisaveis_ids(conversa)
    conversa.account.users.where(id: ids.compact.uniq).select do |pessoa|
      avisaveis.include?(pessoa.id) && ::Autonomia::Automacao::Acesso.alcanca?(pessoa, conversa)
    end
  end

  # Quem a menção avisa (Messages::MentionService): administradores da conta e membros da caixa. Alguém que enxerga a
  # conversa de outro jeito (função, time) seria mencionado sem aviso nenhum.
  def self.avisaveis_ids(conversa)
    conversa.account.administrators.pluck(:id) | conversa.inbox.members.pluck(:id)
  end
end
