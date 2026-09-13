# A ENTREGA DE ARQUIVO JÁ BAIXADA E GRAVADA, na forma que atravessa o adiamento (fatia 1 do PDF rápido,
# rodada 2, 13/09/2026).
#
# O publicador baixa e grava o arquivo ANTES de adiar a publicação (`AsyncPublisher#publicar_arquivo`).
# Quando adia, o que vai para os argumentos do `AsyncPublishJob` é esta forma: a referência assinada do
# blob já gravado, a legenda e o token da entrega. A URL do portal não está nela.
#
# O TOKEN VIAJA PRONTO, calculado pelo publicador sobre a entrega de arquivo original
# (`EntregaPublicada.token_de`, que usa `EntregaDeArquivo#identidade`). Recalculá-lo aqui exigiria a URL.
class Autonomia::Agents::Tools::ArquivoGravado
  CHAVE = 'arquivo_gravado'.freeze
  # `ToolRun#delivery_token`: a `execution_key` da execução, dois pontos e 16 dígitos hexadecimais.
  TOKEN = /\A(?<execucao>[^:]+):[0-9a-f]{16}\z/

  attr_reader :blob_assinado, :legenda, :token

  # -> a forma, quando `valor` é uma (o objeto ou o Hash serializado); nil para qualquer outra coisa.
  def self.de(valor)
    return valor if valor.is_a?(self)
    return nil unless valor.is_a?(Hash)

    forma = valor.deep_stringify_keys[CHAVE]
    return nil unless forma.is_a?(Hash)

    new(blob_assinado: forma['blob'], legenda: forma['legenda'], token: forma['token'])
  end

  def initialize(blob_assinado:, legenda:, token:)
    @blob_assinado = blob_assinado.to_s
    @legenda = legenda.to_s.strip
    @token = token.to_s
  end

  # -> a forma é desta execução e tem o que a publicação precisa? Não confere o blob (ver `blob`).
  def valida_para?(run)
    legenda.present? && blob_assinado.present? && token.match(TOKEN)&.[](:execucao) == run.execution_key
  end

  # -> o blob, quando a assinatura confere, ele existe e leva a marca desta execução com a finalidade da
  # entrega de arquivo (`EntregaDeArquivo.marca`); nil em qualquer outro caso.
  def blob(run)
    encontrado = ActiveStorage::Blob.find_signed(blob_assinado)
    return nil if encontrado.nil?

    marca = encontrado.metadata.to_h
    dono = marca[::Autonomia::Agents::Tools::EntregaDeArquivo::EXECUCAO_CHAVE] == run.id
    finalidade = marca[::Autonomia::Agents::Tools::EntregaDeArquivo::FINALIDADE_CHAVE] == ::Autonomia::Agents::Tools::EntregaDeArquivo::FINALIDADE
    dono && finalidade ? encontrado : nil
  end

  def to_h
    { CHAVE => { 'blob' => blob_assinado, 'legenda' => legenda, 'token' => token } }
  end
end
