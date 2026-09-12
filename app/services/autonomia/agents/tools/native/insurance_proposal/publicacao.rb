# O QUE JÁ VIROU MENSAGEM, E O QUE AINDA PODE VIRAR (entrega 8, rodadas 3 e 4).
#
# A proposta é um arquivo que sai de uma COTAÇÃO, e entre o pedido e a mensagem há minutos: a
# publicação é ADIADA enquanto a cadeia de entrega humanizada do turno não drena (até 90 s) e pode
# ser RETOMADA depois, por um envio pendente que o varredor recupera. Nenhum desses dois caminhos
# passa de novo pelo `poll` — e a cotação pode ter sido refeita no meio. Este módulo é a última
# palavra da ferramenta antes de a mensagem existir, e a identidade pela qual ela reconhece o que é
# seu: o TOKEN (`ToolRun#delivery_token`, `execution_key` + digest do conteúdo).
module Autonomia::Agents::Tools::Native::InsuranceProposal::Publicacao
  extend ActiveSupport::Concern

  # ESTA ENTREGA AINDA PODE SER PUBLICADA? Perguntado pelo publicador sob o lock, imediatamente antes
  # de criar a mensagem (`AutorizacaoDaExecucao`).
  #
  # SÓ AS PROPOSTAS SÃO BARRADAS. A mesma execução publica as frases que EXPLICAM o que houve ("a
  # cotação foi refeita") e os fechos do job; barrá-las deixaria o cliente em silêncio depois de "já
  # estou buscando", que é o defeito oposto.
  #
  # O QUE ESTA CONFERÊNCIA LEVANTAR MORRE AQUI (rodada 4, menor 4 do verificador cego). Ela lê o
  # banco (as cotações da conversa), e uma exceção subindo daqui virava `blocked` no publicador para
  # QUALQUER entrega daquela execução — inclusive as frases, e o cliente ficava mudo. A decisão, na
  # dúvida, é a do dinheiro: o que não se consegue conferir NÃO sai. A frase, que não é da origem,
  # já respondeu `true` antes de a conferência começar.
  def publicavel?(run, entrega)
    return true unless da_origem?(run, entrega)

    origem_ainda_vale?
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] conferencia de origem falhou run=#{run.id} #{e.class}; a proposta nao sai")
    false
  end

  # A ENTREGA QUE UMA MENSAGEM JÁ PUBLICADA CARREGA, achada pelo token dela (rodada 4, P1 do Codex).
  # A retomada de um envio pendente não tem a entrega em mãos — tem a MENSAGEM —, e sem a entrega não
  # há como perguntar `publicavel?`: um `SendReplyJob` reenfileirado entregava ao cliente o arquivo
  # de uma cotação já refeita. Quem sabe reconhecer o próprio conteúdo pelo token é a ferramenta.
  # -> a entrega (arquivo ou reserva), ou nil quando o token não é de uma proposta desta execução.
  def entrega_do_token(run, token)
    sufixo = run.handle.to_h['sufixo']
    proposta = geradas(run.handle.to_h).detect { |gerada| token_de(run, gerada, sufixo) == token }
    proposta && entrega(proposta, sufixo)
  end

  private

  # A ENTREGA SAIU DESTA ORIGEM? Comparação de dado NOSSO contra dado NOSSO: a URL que este handle
  # gravou. A proposta viaja como ARQUIVO (a URL do portal) ou, quando a forma não cabe, como o
  # texto de reserva que termina na MESMA URL.
  #
  # As geradas vêm pelo método da CLASSE, não pela constante: dentro de um módulo compacto o nome
  # curto `GERADAS` (que mora em `Geracao`) não se resolve, e o `NameError` cairia no `rescue` acima
  # — a proposta pararia de sair por um detalhe de escopo, em silêncio (C7 da auditoria).
  def da_origem?(run, entrega)
    urls = geradas(run.handle.to_h).filter_map { |proposta| proposta['url'].to_s.presence }
    return false if urls.empty?

    arquivo = ::Autonomia::Agents::Tools::EntregaDeArquivo.de(entrega)
    return urls.include?(arquivo.url) if arquivo

    urls.any? { |url| entrega.to_s.end_with?(url) }
  end

  # Existe na conversa a mensagem com o token DESTA entrega? Sem a linha da execução (fora do job)
  # não há `execution_key`, e nada está publicado.
  def publicada?(proposta, sufixo)
    return false if run.nil? || conversation.nil?

    ::Autonomia::Agents::Tools::EntregaPublicada.existe?(conversation, token_de(run, proposta, sufixo))
  end

  # O token com que o publicador carimba a mensagem desta proposta: o do ARQUIVO quando a forma cabe,
  # o do texto de reserva quando não — a identidade é a mesma nos dois caminhos.
  def token_de(execucao, proposta, sufixo)
    arquivo = arquivo_de(proposta, sufixo)
    execucao.delivery_token(arquivo.valida? ? arquivo.identidade : arquivo.reserva)
  end
end
