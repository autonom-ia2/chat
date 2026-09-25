# A BUSCA PAGA DO SEGURADO SAI UMA VEZ POR DOCUMENTO NA CONVERSA (decisão 4 do Rodrigo, 25/09/2026, chat#718).
#
# A conferência (`InsuranceQuote#precheck`) chama `quote/enrich` quando os dados estão completos e falta o que a busca
# pelo documento resolve (nome, nascimento e sexo em auto; o nome nos outros ramos). A busca é paga (BigDataCorp, no
# adapter), e nem o adapter nem o chat guardavam a resposta: medido em 25/09/2026, o adapter só guarda o TOKEN do
# fornecedor (`bigdatacorp/client.ts`, cache de módulo), e cada conferência repetida nas seis rodadas pagava de novo.
#
# Aqui fica guardado, por conversa, O QUE A BUSCA NÃO ACHOU: só nomes de campo, nunca o que ela achou (LGPD, revisão da
# adapters#75), e a chave é um HMAC do produto, do documento e dos campos que faltam, nunca o documento em claro. A
# mesma conferência com os mesmos dados de busca lê daqui e não chama o adapter. Falha da busca não é guardada: a
# próxima tenta de novo, como antes. Sem conversa (Testar, playground), nada é guardado.
#
# NUNCA LEVANTA POR CAUSA DO REDIS: sem ele, a busca roda como antes.
module Autonomia::Insurance::BuscaDoSeguradoGuardada
  CHAVE = 'autonomia:busca_do_segurado:%<conversa>d:%<digest>s'.freeze
  VALIDADE = 24.hours

  module_function

  # `identidade`: o que decide a resposta da busca (produto, documento, campos que faltam). O bloco faz a busca e
  # devolve a lista de campos não achados. -> essa lista, guardada ou nova.
  def buscar(conversa_id, identidade)
    return yield if conversa_id.blank?

    chave = format(CHAVE, conversa: conversa_id, digest: digest(identidade))
    guardada = ler(chave)
    return guardada if guardada

    yield.tap { |nao_achados| gravar(chave, nao_achados) }
  end

  def digest(identidade)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, identidade.to_json)
  end

  def ler(chave)
    valor = Redis::Alfred.get(chave)
    valor && JSON.parse(valor)
  rescue StandardError
    nil
  end

  def gravar(chave, nao_achados)
    Redis::Alfred.setex(chave, Array(nao_achados).to_json, VALIDADE)
  rescue StandardError
    nil
  end

  private_class_method :digest, :ler, :gravar
end
