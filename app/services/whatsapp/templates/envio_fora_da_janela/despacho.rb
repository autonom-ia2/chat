# O `enviar` do ponto único (#1587): NÃO envia. No horário, confere o plano e devolve o metadata que o `MessageSender` do
# Followup manda (`template_params` do upstream), ou o motivo para avisar a equipe.
# 1. plano ainda `criando` (ou `equipe` do pré-voo): relê a caixa sem criar (`criar: false`); aprovado agora, segue;
# 2. todos os campos do plano com valor (o Followup preenche com o `TemplateFields::Resolver`): modelo pela metade
#    confunde o cliente;
# 3. a regra de uso de novo, no horário: modelo do sistema MARKETING só com a 2ª marca ainda ligada (o dono pode ter
#    desligado depois do pré-voo); MARKETING sem contato, com contato que recusou ou número +1 não sai;
# 4. relê o modelo NA META (`DispatchCheck`, o mesmo da campanha): aprovado, mesma categoria e mesma estrutura. Se a
#    Meta não respondeu e a conferência veio da lista guardada, não manda (`conferencia_sem_meta`): a lista pode estar
#    velha (modelo pausado ou recusado depois);
# 5. o registro do envio vai no metadata (`envio_fora_da_janela`) e no log, sem texto do cliente.
class Whatsapp::Templates::EnvioForaDaJanela::Despacho
  Ponto = Whatsapp::Templates::EnvioForaDaJanela
  Regras = Whatsapp::Templates::EnvioForaDaJanela::Regras
  # O `DispatchCheck` conversa com campanha; aqui só precisa do id (para o log) e dos template_params.
  Conferencia = Data.define(:id, :template_params)
  REGISTRO = 'envio_fora_da_janela'.freeze
  SISTEMA = Whatsapp::Templates::EnvioForaDaJanela::Planejador::SISTEMA

  def initialize(inbox:, plano:, valores:, contato:)
    @inbox = inbox
    @plano = plano.to_h.deep_stringify_keys
    @valores = valores.to_h.stringify_keys
    @contato = contato
  end

  def call
    plano = atual
    return equipe(plano['caminho'] == Ponto::CRIANDO ? 'em_analise' : plano['motivo']) unless plano['caminho'] == Ponto::MODELO

    corpo = corpo(plano['campos'].to_h)
    return equipe('campo_sem_valor') if corpo.nil?

    impedimento = impedimento(plano)
    return equipe(impedimento) if impedimento

    conferir(plano, corpo)
  end

  private

  def impedimento(plano)
    Regras.impedimento(account: @inbox.account, categoria: plano['categoria'], sistema: sistema?(plano)) ||
      Regras.impedimento_do_contato(@contato, plano['categoria'])
  end

  # Relido no horário: um modelo da conta pode ter ganho dono do sistema depois do pré-voo.
  def sistema?(plano)
    return true if plano['origem'] == SISTEMA

    perfis = WhatsappTemplateProfile.for_inbox(@inbox).where(name: plano['nome'], language: plano['idioma'])
    perfis.any? { |perfil| perfil.system_owner.present? } || Regras.sistema?(plano['nome'], nil)
  end

  def atual
    return @plano if @plano['caminho'] == Ponto::MODELO

    Ponto.planejar(inbox: @inbox, tipo: @plano['tipo'], com_valor: @plano.dig('opcoes', 'com_valor'),
                   ja_recusado: @plano['ja_recusado'], contato: @contato, criar: false)
  end

  # Na ordem do mapa do plano, cada posição com o valor que veio; uma vazia e nada vai.
  def corpo(campos)
    campos.each_key.with_object({}) do |posicao, corpo|
      valor = @valores[posicao.to_s]
      return nil if valor.to_s.strip.empty?

      corpo[posicao.to_s] = valor.to_s
    end
  end

  def conferir(plano, corpo)
    params = { 'name' => plano['nome'].to_s, 'language' => plano['idioma'].to_s, 'category' => plano['categoria'].to_s,
               'processed_params' => { 'body' => corpo } }
    veredito = Whatsapp::Templates::DispatchCheck.new(Conferencia.new(id: "fora_da_janela:#{@inbox.id}:#{plano['tipo']}",
                                                                      template_params: params), channel: @inbox.channel).call
    return equipe(veredito.reason_code) unless veredito.ok?
    return equipe('conferencia_sem_meta') unless veredito.details.to_h[:lookup_source] == Whatsapp::Templates::DispatchCheck::META

    Ponto::Envio.new(status: :enviar, motivo: nil, metadata: metadata(plano, params, veredito.template))
  end

  def metadata(plano, params, modelo_da_meta)
    registro = registro(plano)
    campos_do_log = registro.map { |chave, valor| "#{chave}=#{valor}" }.join(' ')
    Rails.logger.info("[whatsapp][templates][fora_da_janela] envio inbox_id=#{@inbox.id} #{campos_do_log}")
    {
      'template_name' => params['name'], 'template_language' => params['language'],
      'template_category' => params['category'].downcase, 'template_params_category' => params['category'],
      'template_processed_params' => params['processed_params'],
      'message_body' => Ponto.preencher(texto_da_meta(modelo_da_meta).presence || plano['texto'], params['processed_params']['body']),
      REGISTRO => registro
    }
  end

  # O que fica guardado de cada envio (#1585): o tipo, o caminho, o modelo e o idioma, a categoria, a origem e a autorização
  # vigente. O Followup devolve este hash ao `registrar_envio` depois que a mensagem sai (tabela `whatsapp_out_of_window_sends`).
  def registro(plano)
    { 'tipo' => plano['tipo'], 'caminho' => plano['caminho'], 'escolha' => plano['escolha'], 'modelo' => plano['nome'],
      'idioma' => plano['idioma'], 'categoria' => plano['categoria'], 'origem' => plano['origem'],
      'consentimento_id' => Regras.consentimento_vigente(@inbox.account, plano['categoria']) }
  end

  def texto_da_meta(modelo)
    componentes = Whatsapp::Templates::SendableFormat.hashes(modelo.is_a?(Hash) ? modelo['components'] : nil)
    componentes.find { |item| item['type'].to_s.casecmp?('BODY') }&.dig('text').to_s
  end

  def equipe(motivo)
    Ponto::Envio.new(status: :equipe, metadata: {}, motivo: motivo.to_s)
  end
end
