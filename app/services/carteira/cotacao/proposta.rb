# O envio da proposta de renovação ao segurado (E8, #2901): o modelo da Finalidade `renovacao_proposta`, com o PDF da
# proposta guardado na nota privada (Carteira::Cotacao::Pronta) no topo, com o nome "Proposta de renovação.pdf"
# (Whatsapp::Templates::HeaderMedia.dispatch_file). Sai pela caixa escolhida, com as conferências do envio
# (Carteira::Cotacao::Envio: recusa relida do banco, caixa, modelo aprovado).
#
# Duas portas: sozinho (`quem_envia = sozinho`, logo que a proposta fica pronta; passo `proposta_enviada_sozinha`) e o
# clique em "Enviar" no card (`user`; passo `proposta_enviada` com quem clicou). No máximo uma vez, com o estado honesto:
# - sob a trava do seguro só se confere o passo e se grava o do envio, ANTES de qualquer coisa sair, e a transação fecha
#   ali; a mensagem sai depois, fora da trava. O segundo clique (ou a passada sozinha) encontra o passo e para;
# - saiu: o id da mensagem entra no passo (`mensagem_id`);
# - falha clara, sem mensagem (Carteira::Cotacao::Envio::NaoSaiu, antes da trava ou depois): `proposta_nao_saiu` com o
#   motivo e o aviso à equipe, e o Enviar volta (é o último passo do envio);
# - qualquer outra falha depois da chamada: a mensagem pode ter saído. Nada de `proposta_nao_saiu`: o passo fica
#   `incerta` e a equipe é avisada para conferir na conversa. Nada sai de novo sozinho;
# - o passo sem `mensagem_id` há mais de MINUTOS_PARA_INCERTA (o processo caiu entre a reserva e o envio) também é
#   incerto. Incerta, a tela oferece "Enviar de novo", que grava um passo novo e manda.
# No clique, o que impede vira recusa para a tela (CustomExceptions::CarteiraRecusa): `cotacao_desligada`,
# `proposta_ja_enviada`, `sem_proposta`, o motivo do envio que não saiu ou `proposta_incerta`. Sozinho, nada é levantado.
class Carteira::Cotacao::Proposta
  FINALIDADE = 'renovacao_proposta'.freeze
  ENVIADA = 'proposta_enviada'.freeze
  SOZINHA = 'proposta_enviada_sozinha'.freeze
  NAO_SAIU = 'proposta_nao_saiu'.freeze
  INCERTA = 'proposta_incerta'.freeze
  MINUTOS_PARA_INCERTA = 10
  # O que impede o envio, antes de qualquer coisa sair.
  class Parou < StandardError; end

  def initialize(apolice, config, user: nil)
    @apolice = apolice
    @config = config
    @user = user
  end

  # -> a mensagem enviada, ou nil (sozinho, quando não saiu).
  def enviar
    parar('cotacao_desligada') unless Carteira::Cotacao.aberta?(@apolice.account, @config)
    conferir!
    mandar(*reservar!)
  rescue Parou => e
    raise CustomExceptions::CarteiraRecusa, e.message if @user

    nil
  end

  # A proposta saiu nesta vigência, por uma das duas portas: o último passo do envio é um envio, e não é incerto.
  def self.enviada?(apolice)
    ultimo = apolice.eventos.where(tipo: [ENVIADA, SOZINHA, NAO_SAIU])
                    .where("valores->>'vigencia' = ?", apolice.fim_vigencia.iso8601).order(:quando, :id).last
    [ENVIADA, SOZINHA].include?(ultimo&.tipo) && !incerta?(ultimo)
  end

  # O passo do envio que não se sabe se saiu: a falha veio depois da chamada, ou o id da mensagem não entrou a tempo.
  def self.incerta?(passo)
    valores = passo.valores.to_h
    return true if valores['incerta']

    valores['mensagem_id'].blank? && passo.quando < MINUTOS_PARA_INCERTA.minutes.ago
  end

  private

  def envio
    @envio ||= Carteira::Cotacao::Envio.new(@apolice, @config, user: @user)
  end

  # As conferências do envio antes da trava (recusa, caixa, modelo): o que já se sabe que não sai não reserva nada.
  def conferir!
    envio.conferir!(FINALIDADE)
  rescue Carteira::Cotacao::Envio::NaoSaiu => e
    nao_saiu(e.message)
  end

  # Sob a trava, só o passo: relido, e o do envio gravado com quem clicou antes de qualquer coisa sair. -> [passo, PDF].
  def reservar!
    @apolice.with_lock(requires_new: true) do
      parar('proposta_ja_enviada') if self.class.enviada?(@apolice)
      blob = arquivo || parar('sem_proposta')
      [Carteira::Cotacao.registrar(@apolice, @user ? ENVIADA : SOZINHA, user: @user), blob]
    end
  end

  # Fora da trava: a mensagem com o PDF no topo, e o id dela no passo.
  def mandar(passo, blob)
    topo = ->(caixa) { Whatsapp::Templates::HeaderMedia.dispatch_file(blob, caixa).merge('media_type' => 'document') }
    mensagem = envio.modelo(FINALIDADE, Carteira::Cotacao::ETAPA_PROPOSTA, topo: topo)
    marcar(passo, 'mensagem_id' => mensagem.id)
    mensagem
  rescue Carteira::Cotacao::Envio::NaoSaiu => e
    nao_saiu(e.message)
  rescue StandardError => e
    incerta(passo, e)
  end

  # Pode ter saído: sem `proposta_nao_saiu`, que deixaria mandar em dobro. A equipe confere na conversa.
  def incerta(passo, erro)
    Rails.logger.warn("[carteira][cotacao] proposta incerta apolice=#{@apolice.id} #{erro.class}")
    marcar(passo, 'incerta' => true)
    Carteira::Cotacao::Aviso.new(@apolice, INCERTA).call
    parar(INCERTA)
  end

  def marcar(passo, valores)
    passo.update!(valores: passo.valores.to_h.merge(valores))
  end

  # O PDF da proposta pronta desta vigência: o anexo da nota privada que a guardou.
  def arquivo
    pronta = Carteira::Cotacao.passo(@apolice, Carteira::Cotacao::Pronta::PRONTA)
    nota = pronta && Message.find_by(id: pronta.valores.to_h['nota'], account_id: @apolice.account_id)
    nota&.attachments&.first&.file&.blob
  end

  def nao_saiu(motivo)
    Carteira::Cotacao.registrar(@apolice, NAO_SAIU, motivo: 'envio', detalhe: motivo)
    Carteira::Cotacao::Aviso.new(@apolice, 'proposta_nao_saiu', detalhe: motivo).call
    parar(motivo)
  end

  def parar(codigo)
    raise Parou, codigo
  end
end
