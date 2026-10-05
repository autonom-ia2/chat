# A pergunta que o Guia manda ao modelo: contexto + a fala da pessoa.
#
# O PromptBuilder corta a pergunta montada pelo FIM (MAX_COMPOSED_QUERY_CHARS), e o fim é a fala.
# Com tela e memória cheias o contexto passa do teto; quem cede é o contexto, nunca a fala.
module Autonomia::Guide::PerguntaMontada
  def self.call(contexto, mensagem)
    fala = "\n\n#{mensagem}"
    espaco = ::Autonomia::Agents::Config::MAX_COMPOSED_QUERY_CHARS - fala.length
    return fala.lstrip unless espaco.positive?

    "#{::Autonomia::Agents::Config.truncate_text(contexto, espaco)}#{fala}"
  end
end
