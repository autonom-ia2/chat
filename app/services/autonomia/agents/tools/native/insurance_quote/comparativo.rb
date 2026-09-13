# O COMPARATIVO EM PDF COMO ARQUIVO NA CONVERSA (entrega 11 do Agente de Cotação).
#
# Até 11/09/2026 o comparativo saía como texto com o link do portal. Quem está no WhatsApp espera o
# arquivo: um link é uma aba, um arquivo é o que ele guarda e reencaminha. A ferramenta continua
# sem baixar nada — ela não conhece conversa nem mensagem —: entrega a URL que o portal gerou, o
# NOME que o arquivo vai ter e a legenda que sai com ele, e o publicador (`AsyncPublisher`) baixa na
# hora de publicar.
#
# O LINK DO PORTAL NÃO VAI AO CLIENTE (fatia 1 do PDF rápido, 13/09/2026). A URL do portal não tem
# assinatura, leva o nome do segurado no caminho e baixa com HTTP 200 sem autenticação. Até essa data,
# quando o arquivo não baixava, o publicador mandava o texto de reserva com a URL; agora ele não publica
# nada, e baixa ANTES de adiar (rodada 2): o download que falha volta recusado na mesma passada, o motor
# não encerra e `fechar` pede outro comparativo na passada seguinte, até `TETO_DE_TENTATIVAS`. O que o
# `AsyncPublishJob` ainda pode recusar depois de adiar é só o anexo do blob já gravado (autorização caída,
# erro de banco), e isso não ganha nova tentativa.
#
# Separado da ferramenta pelo mesmo motivo de `Declaracao`, `Recusas`, `Envio` e `Veiculo`: é outro
# assunto (como o comparativo chega ao cliente), e a classe está no teto de linhas.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Comparativo
  extend ActiveSupport::Concern

  # As duas constantes de RECUO dos papéis `comparativo_legenda` e `comparativo_reserva`: em
  # produção quem as escreve é o especialista, no pedido (`InsuranceQuote::Frases`).
  LEGENDA = 'Comparativo com todas as opções.'.freeze
  # A frase da reserva continua existindo: é a constante de recuo do papel `comparativo_reserva`, que
  # continua no pedido, e a forma da entrega de arquivo exige uma reserva. Ela não é publicada.
  RESERVA = 'Comparativo com todas as opções:'.freeze
  NOME = 'Comparativo de seguro'.freeze
  # Quantas vezes esta execução já pediu o comparativo ao portal na passada que fecha a cotação. Contado
  # por `fechar` antes de cada pedido; vai à linha junto da identidade do comparativo emitido, ou no
  # `record_attempt!` do fim da passada.
  TENTATIVAS_KEY = 'comparativo_tentativas'.freeze
  # O TETO DE PEDIDOS DO COMPARATIVO AO PORTAL, e por que três. Medido em 13/09/2026: 1 de 5 pedidos
  # voltou 504, em 29 s; se as falhas forem independentes nessa taxa (não foi medido), três seguidas
  # acontecem em 0,8% das cotações. O TETO NÃO GARANTE TEMPO: no pior caso cada passada de nova tentativa
  # custa o intervalo de consulta (21 s no fim da progressão), a leitura do portal (até 65 s,
  # `Connector::Http::READ_TIMEOUT` mais `OPEN_TIMEOUT`), o pedido do comparativo (outros 65 s) e o
  # download (20 s, `EntregaDeArquivo::PRAZO_SEGUNDOS`), ~171 s — e o prazo de 420 s pode vencer no meio
  # das tentativas. O prazo só é conferido no começo de uma passada (`AsyncRunJob#stop?`); vencido, quem
  # encerra é `AsyncRunJob#fail_run`, e o encerramento pede o comparativo mais uma vez quando ainda há
  # tentativa sobrando (`Fecho#closing_deliveries`).
  TETO_DE_TENTATIVAS = 3

  private

  # A PASSADA QUE FECHA A COTAÇÃO. -> Tools::Progress.
  #   - sem comparativo a tentar (`comparativo_por_tentar?` falso: nenhum preço emitido, comparativo
  #     assumido, ou teto atingido): `done` com as entregas da passada;
  #   - comparativo gerado: `done` com ele no fim das entregas, e as marcas dele no handle. Se o
  #     publicador não o aceitar, o motor não encerra (`AsyncRunJob#apply`) e a passada seguinte volta
  #     aqui para decidir por `comparativo_por_tentar?`;
  #   - comparativo que não saiu do portal: `running` enquanto ainda houver tentativa, `done` depois.
  #
  # As marcas só entram no handle depois de a entrega existir na forma em que vai sair
  # (`Progress.entregavel`), e é sobre essa forma que a identidade é calculada.
  #
  # A IDENTIDADE E A CONTAGEM VÃO À LINHA ANTES DE O ARQUIVO SER PUBLICADO. O handle que esta passada
  # devolve só chega ao banco no `record_attempt!` do fim dela, depois da publicação. Morto o processo
  # entre as duas coisas (o Sidekiq reenfileira o job no hard shutdown de um deploy), a mesma passada
  # rodava de novo sem a identidade, pedia outro comparativo ao portal, que devolve outra URL e com ela
  # outra identidade, e o cliente recebia dois PDFs. Com a identidade na linha, a reentrada pergunta por
  # ela (`comparativo_assumido?`). A escrita é reforço (`gravar_na_linha`): se falhar, as marcas seguem no
  # handle da passada. Duas passadas SIMULTÂNEAS sobre a mesma linha ainda pedem dois comparativos: as
  # duas leem a linha antes de qualquer uma gravar.
  def fechar(deliveries, handle)
    return concluir_passada(deliveries, handle) unless comparativo_por_tentar?(handle)

    handle = handle.merge(TENTATIVAS_KEY => handle[TENTATIVAS_KEY].to_i + 1)
    pdf = gerar_comparativo(handle)
    entrega = pdf && progress_class.entregavel(pdf)
    return sem_comparativo(deliveries, handle) if entrega.nil?

    marcas = marcas_do_comparativo(entrega).merge(TENTATIVAS_KEY => handle[TENTATIVAS_KEY])
    gravar_na_linha { run.merge_handle!(marcas) } if run
    concluir_passada(deliveries + [entrega], handle.merge(marcas))
  end

  # O comparativo desta passada não saiu: `running` se ainda há tentativa, `done` se não há.
  def sem_comparativo(deliveries, handle)
    return progress_class.running(deliveries: deliveries, handle: handle) if comparativo_por_tentar?(handle)

    concluir_passada(deliveries, handle)
  end

  # `done`, com `Fecho::CONCLUSAO_KEY` no handle (ver `Fecho#resta_entregar?`) e, quando o comparativo
  # desta execução já foi assumido pelo publicador, `PDF_SENT_KEY` — gravada aqui, e não na emissão.
  def concluir_passada(deliveries, handle)
    marcas = { self.class::CONCLUSAO_KEY => true }
    marcas[self.class::PDF_SENT_KEY] = true if comparativo_assumido?(handle)
    progress_class.done(deliveries: deliveries, handle: handle.merge(marcas))
  end

  # -> verdade quando há preço emitido, o teto não foi atingido e o comparativo não foi assumido.
  # Também é lida por `Fecho#resta_entregar?`.
  def comparativo_por_tentar?(handle)
    return false if Array(handle[self.class::DELIVERED_KEY]).empty?
    return false if handle[TENTATIVAS_KEY].to_i >= TETO_DE_TENTATIVAS

    !comparativo_assumido?(handle)
  end

  # -> verdade quando a identidade do comparativo emitido (`COMPARATIVO_KEY`) está na lista do aceite OU
  # numa mensagem da conversa. O aceite de uma entrega de arquivo só existe quando o arquivo foi baixado e
  # gravado: o publicador baixa antes de publicar e antes de adiar (`AsyncPublisher::Arquivos`).
  #
  # A MENSAGEM CONTA MESMO SEM ACEITE, e o caso é real: o publicador cria a mensagem com o arquivo e,
  # quando o `SendReplyJob` não entra na fila, devolve `blocked` com a pendência gravada na mensagem — o
  # varredor a retoma (`ReapStaleRunsJob#retomar_envios_pendentes`). Cada pedido ao portal devolve uma
  # URL DIFERENTE (medido em 13/09/2026: dois pedidos da mesma cotação, duas URLs), e com ela uma
  # identidade diferente; pedir outro comparativo ali poria um segundo PDF na conversa.
  #
  # SEM IDENTIDADE GRAVADA, vale a sentinela `PDF_SENT_KEY`: é o handle da ferramenta montada sem execução
  # (que não grava token) e o da linha gravada pela versão anterior sem token.
  def comparativo_assumido?(handle)
    token = handle[self.class::COMPARATIVO_KEY]
    return handle[self.class::PDF_SENT_KEY].present? if token.blank?

    aceita?(token) || ::Autonomia::Agents::Tools::EntregaPublicada.para(run&.conversation, token).present?
  end

  # UM PEDIDO DO COMPARATIVO AO PORTAL. -> a entrega de arquivo na forma serializada, ou nil quando a
  # geração falha, quando o portal não devolve URL ou quando a URL não cabe na forma. Nunca levanta:
  # os preços já chegaram, e um PDF que não sai não pode apagá-los.
  def gerar_comparativo(handle)
    proposal = sessions.with_fresh_session do |open_session|
      connector.quote_proposal(provider: connection.provider, session: open_session,
                               quote_id: handle['quote_id'])
    end
    url = proposal.to_h['url'].presence
    url && entrega_do_comparativo(url)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] comparativo falhou account=#{account.id} #{e.class}")
    nil
  end

  # A URL VEM DE FORA e a forma da entrega de arquivo pode recusá-la (o adapter só garante que é uma
  # URL; https não é promessa dele). Recusada, devolve nil — o comparativo não saiu — e o defeito vai
  # ao log pelo nome do campo, nunca pelo valor.
  #
  # A URL SÓ ENTRA EM `url`, de onde o publicador baixa. A legenda e a reserva são as frases do
  # especialista depuradas pela mesma função da saída (`depurar`), sem o link. A identidade de uma
  # entrega de arquivo é `"arquivo:#{url}"` (`EntregaDeArquivo#identidade`): legenda e reserva não a
  # alteram.
  def entrega_do_comparativo(url)
    entrega = ::Autonomia::Agents::Tools::EntregaDeArquivo.new(
      url: url, nome: nome_do_comparativo, legenda: depurar(frases[:comparativo_legenda]).to_s,
      reserva: depurar(frases[:comparativo_reserva]).to_s
    )
    return entrega.to_h if entrega.valida?

    Rails.logger.warn("[autonomia][insurance] comparativo sem forma de arquivo account=#{account.id} " \
                      "defeito=#{entrega.defeito}; nao sai")
    nil
  end

  # O NOME DIZ O QUE O ARQUIVO É, para o cliente achá-lo depois (termo 5): "Comparativo de seguro,
  # placa HIK9383.pdf". A placa é o dado que ele mesmo informou e já vê na conversa; nada de CPF,
  # nome ou CEP. Sem placa (chassi, FIPE, outro ramo) vai o ramo, com espaço no lugar do sublinhado
  # do código — o nome é para uma pessoa ler.
  #
  # VÍRGULA, E NÃO TRAVESSÃO NEM DOIS PONTOS (decisão do CEO, 12/09/2026): o travessão sai do que
  # chega ao cliente, e dois pontos o Windows recusa em nome de arquivo — a validação da forma
  # (`EntregaDeArquivo::NOME_DE_PDF`) só barra `/` e `\`, então quem barraria seria o sistema
  # operacional dele, na hora de salvar.
  def nome_do_comparativo
    placa = quote_input.to_h.dig('vehicle', 'plate').to_s.upcase.gsub(/[^A-Z0-9]/, '')
    sufixo = placa.present? ? "placa #{placa}" : produto.tr('_', ' ')
    "#{NOME}, #{sufixo}.pdf"
  end
end
