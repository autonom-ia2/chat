# O COMPARATIVO EM PDF COMO ARQUIVO NA CONVERSA (entrega 11 do Agente de Cotação).
#
# Até 11/09/2026 o comparativo saía como texto com o link do portal. Quem está no WhatsApp espera o
# arquivo: um link é uma aba, um arquivo é o que ele guarda e reencaminha. A ferramenta continua
# sem baixar nada — ela não conhece conversa nem mensagem —: entrega a URL que o portal gerou, o
# NOME que o arquivo vai ter, a legenda que sai com ele e a RESERVA (o texto com o link, palavra
# por palavra o de antes), e o publicador (`AsyncPublisher`) baixa na hora de publicar. Quando o
# download falha, sai a reserva: a falha do arquivo não apaga os preços que já saíram.
#
# Separado da ferramenta pelo mesmo motivo de `Declaracao`, `Recusas`, `Envio` e `Veiculo`: é outro
# assunto (como o comparativo chega ao cliente), e a classe está no teto de linhas.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Comparativo
  extend ActiveSupport::Concern

  # As duas constantes de RECUO dos papéis `comparativo_legenda` e `comparativo_reserva`: em
  # produção quem as escreve é o especialista, no pedido (`InsuranceQuote::Frases`).
  LEGENDA = 'Comparativo com todas as opções.'.freeze
  # A reserva é o texto de antes, sem tirar nem pôr: "o link vai como hoje" é o termo 2.
  RESERVA = 'Comparativo com todas as opções:'.freeze
  NOME = 'Comparativo de seguro'.freeze

  private

  # nil quando não há o que imprimir, quando já foi enviado, ou quando a geração falha. Nunca
  # derruba a cotação: os preços já chegaram, e um PDF que não sai não pode apagá-los.
  # -> a entrega de arquivo na forma serializada (é ela que atravessa o handle e o job), ou o TEXTO
  # com o link quando a URL do portal não cabe na forma (ver `entrega_do_comparativo`).
  def comparison_pdf(handle)
    return if handle[self.class::PDF_SENT_KEY]
    return if Array(handle[self.class::DELIVERED_KEY]).empty?

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
  # URL; https não é promessa dele). A recusa da forma NÃO pode apagar a entrega: quem chama grava a
  # sentinela do comparativo assim que algo sai daqui, e um Hash inválido seria descartado adiante
  # (`Progress`, publicador) com o cliente sem arquivo e sem link. Então o que sai é a reserva — o
  # texto com o link, o de antes — e o defeito da forma vai ao log, pelo nome do campo.
  # OS DOIS TEXTOS DELA SÃO DO ESPECIALISTA, e passam pela mesma depuração do resto do que sai daqui
  # — é ela que decide o texto final, e é do texto final que nasce a identidade da entrega. A URL
  # entra depois da depuração, porque o corte por tamanho não pode cair no meio de um link.
  def entrega_do_comparativo(url)
    entrega = ::Autonomia::Agents::Tools::EntregaDeArquivo.new(
      url: url, nome: nome_do_comparativo, legenda: depurar(frases[:comparativo_legenda]).to_s,
      reserva: "#{depurar(frases[:comparativo_reserva])}\n#{url}"
    )
    return entrega.to_h if entrega.valida?

    Rails.logger.warn("[autonomia][insurance] comparativo sem forma de arquivo account=#{account.id} " \
                      "defeito=#{entrega.defeito}; vai como link")
    entrega.reserva
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
