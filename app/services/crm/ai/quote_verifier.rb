# A regra anti-invenção do prompt manda a IA copiar um trecho LITERAL da conversa para provar o
# open_loop que está citando. Extraído de Crm::FollowUps::AutoFollowupRunner para ser reusado por
# todo caminho que aceita composição do mesmo schema (AutoFollowupRunner, CallbackRunner) — a
# trava anti-alucinação não pode existir num caminho e faltar no outro que fala com o cliente.
#
# Sem estado, sem I/O: só compara texto normalizado. `messages` é o `context[:recent_messages]`
# do Crm::Ai::ContextBuilder (array de hashes com :content).
class Crm::Ai::QuoteVerifier
  # Citação curta demais não prova nada ("ok", "sim") e casaria com quase qualquer conversa.
  MIN_QUOTE_LENGTH = 15

  def initialize(quote:, messages:)
    @quote = normalize_for_quote(quote)
    @messages = messages
  end

  def verified?
    return false if @quote.length < MIN_QUOTE_LENGTH

    # Cópia encaminhada pela equipe (#1760) é texto de outra pessoa: não prova pendência desta conversa.
    Array(@messages).reject { |message| message[:forwarded] }
                    .any? { |message| normalize_for_quote(conteudo(message)).include?(@quote) }
  end

  private

  # #1807: o aviso de autoria do e-mail é nosso, não da conversa: nunca serve de citação. A mensagem de outra pessoa
  # em cópia continua valendo (o follow-up pode retomar a pergunta dela).
  def conteudo(message)
    message[:email_autoria] ? Crm::Email::Autoria.sem_aviso(message[:content]) : message[:content]
  end

  # Acento, caixa e espaçamento variam entre o que o modelo devolve e o que está gravado.
  # Comparar cru reprovaria citação honesta.
  def normalize_for_quote(text)
    I18n.transliterate(text.to_s).downcase.gsub(/\s+/, ' ').strip
  end
end
