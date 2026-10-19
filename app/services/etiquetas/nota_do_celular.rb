# Nota de atividade na conversa quando o WhatsApp do celular põe ou tira uma etiqueta (#1823, F1b, protótipo aprovado):
# "O WhatsApp do celular adicionou/removeu a etiqueta X", no idioma da conta e no mesmo formato das notas de etiqueta do
# Chatwoot (Conversations::ActivityMessageJob, tipo activity). X é o nome legível, na ordem do painel (helper
# nomeDaEtiqueta.js): nome livre, senão o nome do celular, senão o derivado do título ("aguardando_retorno" vira
# "Aguardando retorno"), sem regex. Montada sob as travas e enfileirada por quem chama, depois do commit.
class Etiquetas::NotaDoCelular
  CHAVES = { adicionar: 'adicionada', remover: 'removida' }.freeze

  def initialize(conversa:, registro:, operacao:)
    @conversa = conversa
    @registro = registro
    @operacao = operacao
  end

  def enfileirar
    Conversations::ActivityMessageJob.perform_later(
      @conversa,
      { account_id: @conversa.account_id, inbox_id: @conversa.inbox_id, message_type: :activity, content: conteudo }
    )
  end

  private

  def conteudo
    I18n.with_locale(idioma_da_conta) do
      I18n.t("etiquetas_do_celular.atividade.#{CHAVES.fetch(@operacao)}", etiqueta: nome_legivel)
    end
  end

  def idioma_da_conta
    locale = @conversa.account.locale.presence&.to_sym
    I18n.available_locales.include?(locale) ? locale : I18n.default_locale
  end

  def nome_legivel
    Etiquetas::Nome.find_by(label_id: @registro.label_id)&.nome.presence || @registro.nome.presence || nome_do_titulo
  end

  def nome_do_titulo
    palavras = @registro.label.title.split('_').compact_blank.join(' ')
    palavras[0].to_s.upcase + palavras[1..].to_s
  end
end
