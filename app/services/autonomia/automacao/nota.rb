# Nota privada da Automação na conversa, mencionando quem deve ver (#2414 F4). A menção é o aviso que a plataforma já
# tem (Messages::MentionService): sino, push e e-mail pela preferência de cada pessoa, abrindo a conversa. O cliente
# nunca vê. Sai sem remetente e com a marca da automação, como a mensagem.
class Autonomia::Automacao::Nota
  # O que o editor do painel escapa ao gravar uma menção (prosemirror-markdown 1.13, `esc`).
  ESCAPADOS = ['`', '*', '\\', '~', '[', ']', '_'].freeze
  # O `\w` do editor (JavaScript): letras ASCII, algarismos e `_`.
  LETRAS_DE_PALAVRA = [*'a'..'z', *'A'..'Z', *'0'..'9', '_'].freeze

  def self.criar(conversa:, texto:, pessoas:, marca:)
    mencoes = pessoas.map { |pessoa| mencao(pessoa) }
    conteudo = [texto, mencoes.join(' ').presence].compact.join("\n\n")
    ::Messages::MessageBuilder.new(nil, conversa, content: conteudo, private: true, content_attributes: marca).perform
  end

  # A menção como o editor do painel a grava: `[@Nome](mention://user/ID/Nome codificado)`, com o mesmo escape. Nome
  # com `]` ou `)` não quebra o link.
  def self.mencao(pessoa)
    "[#{escapar("@#{pessoa.name}")}](#{escapar("mention://user/#{pessoa.id}/#{ERB::Util.url_encode(pessoa.name)}")})"
  end

  # Barra antes de cada caractere escapado; o `_` entre letras ou números fica como está, como no editor.
  def self.escapar(texto)
    letras = texto.chars
    letras.each_with_index.map do |letra, i|
      meio_de_palavra = letra == '_' && i.positive? && palavra?(letras[i - 1]) && palavra?(letras[i + 1])
      ESCAPADOS.include?(letra) && !meio_de_palavra ? "\\#{letra}" : letra
    end.join
  end

  def self.palavra?(letra) = LETRAS_DE_PALAVRA.include?(letra)

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
