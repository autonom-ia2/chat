# Recusa da Meta, parte do Meta::AdsGraphClient: o resultado e a linha do log. Toda recusa fica no log com o caminho, o
# código e a mensagem já limpa: sem isso, um erro que quem chama trata como "ainda não" vira silêncio em produção
# (#1068). O código 100 puro é "parâmetro inválido" para qualquer campo; o que diz qual campo e por quê vem no
# subcódigo, no título e na mensagem para a pessoa, e o fbtrace_id é o que a Meta pede para achar a chamada (#2341).
# O token nunca entra no caminho, e todo texto passa pela limpeza de segredo.
module Meta::AdsGraphClient::Recusa
  FBTRACE_MAX_LENGTH = 32

  private

  def log_failure(verb, path, result)
    return result if result.ok

    Rails.logger.warn("[MetaAdsGraph] #{verb.to_s.upcase} #{path} http=#{result.http_code.inspect} " \
                      "code=#{result.error_code.inspect} message=#{result.error_message}#{failure_details(result)}")
    result
  end

  # Só o que a Meta mandou, na ordem subcódigo, fbtrace, título e mensagem para a pessoa.
  def failure_details(result)
    details = { 'subcode' => result.error_subcode, 'fbtrace' => result.fbtrace_id }.compact.map { |key, value| " #{key}=#{value}" }
    texts = { 'user_title' => result.error_user_title, 'user_msg' => result.error_user_msg }.compact
    (details + texts.map { |key, value| " #{key}=\"#{one_line(value)}\"" }).join
  end

  # Texto da Meta numa linha só e sem aspas duplas: não quebra a linha do log nem imita outro campo.
  def one_line(text)
    text.squish.tr('"', "'")
  end

  def failure_result(response, error, usage)
    Meta::AdsGraphClient::Result.new(
      ok: false, http_code: response.code, data: nil, error_code: error['code'], error_subcode: error['error_subcode'],
      usage_headers: usage, error_message: sanitize(error['message'].presence || "HTTP #{response.code}"),
      error_user_title: sanitize(error['error_user_title'].presence), error_user_msg: sanitize(error['error_user_msg'].presence),
      fbtrace_id: trace_id(error['fbtrace_id'])
    )
  end

  # O fbtrace_id é curto, de letras, números, _ e -. Fora disso, não é o que a Meta costuma mandar e não vai ao log.
  def trace_id(value)
    return if value.blank?

    text = value.to_s
    text.length <= FBTRACE_MAX_LENGTH && text.delete('A-Za-z0-9_\-').empty? ? text : '<REDACTED>'
  end
end
