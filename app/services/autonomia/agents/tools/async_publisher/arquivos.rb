# A ENTREGA DE ARQUIVO NO PUBLICADOR: baixar, gravar, adiar ou anexar (entrega 11; rodada 2 da fatia 1
# do PDF rápido, 13/09/2026).
#
# O ARQUIVO É BAIXADO E GRAVADO ANTES DE A PUBLICAÇÃO SER ADIADA. Até a rodada 2 o publicador adiava a
# entrega de arquivo sem baixar nada, e o download acontecia no `AsyncPublishJob`, depois de o motor ter
# lido o adiamento como aceite: um download que falhava ali deixava o cliente sem PDF, com o fecho
# publicado, e ninguém pedia outro. Agora `publicar_arquivo` baixa e grava primeiro; o download que falha
# volta `blocked` para quem chamou, na mesma passada, e a publicação adiada carrega o blob já gravado
# (`ArquivoGravado`), não a URL.
#
# O ARQUIVO BAIXA E É GRAVADO FORA DO LOCK da conversa: é rede, com tetos próprios, e a conversa não pode
# ficar travada por ele. Gravar ANTES da mensagem põe a falha do armazenamento dentro da mesma fronteira
# que a do download: o ActiveStorage subiria o arquivo só no `after_commit` da mensagem, e uma subida que
# falhasse ali deixaria a legenda no ar com um anexo sem bytes e o token já publicado (rodada 3,
# 11/09/2026). O motivo vai ao log com o código curto e a classe da causa, nunca o texto da resposta nem
# da exceção.
#
# O BLOB QUE NÃO VIRA ANEXO nem é repassado ao adiamento (o retry que encontrou a mensagem no ar, a
# publicação que não concluiu, a autorização que caiu no caminho) vai para a limpeza EM SEGUNDO PLANO
# (`EntregaDeArquivo.agendar_limpeza`, que registra e não levanta quando a fila recusa — rodadas 4 e 5).
# O blob repassado ao adiamento e nunca anexado (o job perdido com o Redis) fica com a MARCA da execução,
# e o varredor o apaga depois de `ReapStaleRunsJob::BLOB_SEM_DONO_IDADE` (`blobs_sem_dono`).
module Autonomia::Agents::Tools::AsyncPublisher::Arquivos
  private

  # A entrega de arquivo com a URL: baixa e grava, e então adia (cadeia aberta, com `wait_for_chain`) ou
  # anexa. -> `deferred` com o `ArquivoGravado` em `adiada`, o resultado de `publicar_gravado`, ou o de
  # `sem_arquivo` quando o arquivo não pôde ser baixado ou gravado.
  def publicar_arquivo(conversation, arquivo, wait_for_chain)
    token = token_de(arquivo)
    blob = arquivo.gravar(run_id: @run.id)
    gravado = ::Autonomia::Agents::Tools::ArquivoGravado.new(blob_assinado: blob.signed_id, legenda: arquivo.legenda, token: token)
    cadeia_aberta = wait_for_chain && humanized_chain_open?(conversation)
    # Daqui em diante o blob é de quem recebe a forma: o adiamento ou `publicar_gravado`, que tem a
    # própria limpeza.
    repassado = true
    return adiar(gravado) if cadeia_aberta

    publicar_gravado(conversation, gravado, blob)
  rescue ::Autonomia::Agents::Tools::EntregaDeArquivo::Indisponivel => e
    Rails.logger.warn("[autonomia][tool][async] arquivo indisponivel run=#{@run.id} motivo=#{e.motivo}" \
                      "#{" causa=#{e.causa}" if e.causa}; nao publicado")
    sem_arquivo(conversation, token)
  ensure
    agendar_limpeza_do_blob(blob) if blob && !repassado
  end

  # O arquivo já gravado: anexa o blob a uma mensagem com a legenda e o token. `blob` é o que
  # `publicar_arquivo` acabou de gravar, ou o que a forma adiada aponta (`ArquivoGravado#blob`, nil quando
  # a assinatura não confere, o blob sumiu ou não é desta execução — aí vai a `sem_arquivo`).
  def publicar_gravado(conversation, gravado, blob = gravado.blob(@run))
    return sem_arquivo(conversation, gravado.token) if blob.nil?

    anexado = false
    resultado, anexado = publicar_anexo(conversation, gravado, blob)
    resultado
  ensure
    agendar_limpeza_do_blob(blob) if blob && !anexado
  end

  # -> [Result, o blob ficou com dono?]. O blob tem dono quando a mensagem NOVA saiu com ele, ou quando
  # está anexado a uma mensagem que ficou no banco (a publicação reconciliada depois do commit, com ou sem
  # envio; e o retry da forma adiada que acha a mensagem que ela mesma criou). O retry que achou a mensagem
  # no ar com outro blob e a publicação recusada sob o lock não dão dono: o blob vai para a limpeza.
  #
  # A FALHA AO ANEXAR sem mensagem no banco (a transação voltou: anexo inválido, banco) vai a
  # `sem_arquivo`, registrada com a classe da causa (rodada 6, 11/09/2026). Se `sem_arquivo` também
  # levantar, sobe para o `publish`, que devolve `blocked`.
  def publicar_anexo(conversation, gravado, blob)
    resultado = post(conversation, self.class::Corpo.new(texto: gravado.legenda, token: gravado.token, anexo: blob.signed_id))
    [resultado, resultado.message.present? || blob.attachments.exists?]
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] anexo falhou run=#{@run.id} causa=#{e.class}; nao publicado")
    [sem_arquivo(conversation, gravado.token), false]
  end

  # O ARQUIVO QUE NÃO PÔDE SER PUBLICADO: nenhuma mensagem nova, e o link do portal NÃO vai no lugar
  # (fatia 1 do PDF rápido — a URL não tem assinatura, leva o nome do segurado no caminho e baixa sem
  # autenticação). Passa pelo mesmo `post` — lock, autorização, busca pelo token — com um corpo SEM TEXTO,
  # que `publicar_sob_lock` nunca transforma em mensagem: se a mensagem com este token já está na conversa,
  # devolve o que `retomar` devolver; se não está, `blocked`.
  def sem_arquivo(conversation, token)
    post(conversation, self.class::Corpo.new(texto: nil, token: token))
  end

  # A execução não pode mais publicar (conferência de entrada, `authorized_conversation`). -> `blocked`.
  # Um arquivo já gravado que chega aqui pelo adiamento não vai virar anexo: o blob vai para a limpeza.
  def recusar_na_entrada(forma)
    if forma.is_a?(::Autonomia::Agents::Tools::ArquivoGravado)
      blob = forma.blob(@run)
      agendar_limpeza_do_blob(blob) if blob && !blob.attachments.exists?
    end
    self.class::Result.new(status: :blocked)
  end

  def agendar_limpeza_do_blob(blob)
    ::Autonomia::Agents::Tools::EntregaDeArquivo.agendar_limpeza(blob, contexto: "run=#{@run.id}")
  end
end
