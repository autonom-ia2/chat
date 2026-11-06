# O passo "mensagem" (#2414 F4): manda texto ao cliente na conversa alvo. Sai como "Automação" (D9): sem remetente,
# com a marca da automação (`automacao_id`), que a lista única de envios automáticos reconhece
# (Autonomia::Agents::Operate::PessoaDaEquipe). O cliente recebe uma mensagem normal da empresa.
#
# Pula, com o motivo no registro:
# - valor vazio ou texto que ficou em branco;
# - contato que pediu para não receber (o mesmo campo das campanhas);
# - canal sem resposta (tweet);
# - janela fechada. Vale para todo canal com janela, lida como envio automático (sem a tag de agente humano da Meta,
#   24 h). A caixa híbrida com o WhatsApp API pronto responde fora da janela, em texto. No número oficial, com a janela
#   fechada e um modelo aprovado na receita (F4b, #2468), sai o modelo (Autonomia::Automacao::ModeloWhatsapp); sem
#   modelo, ou fora do número oficial, o motivo continua `fora_da_janela`;
# - limite de horas que o dono pôs na caixa do canal API (`agent_reply_time_window`), vencido: `limite_da_caixa`. Sem
#   esse limite, o canal API responde a qualquer hora.
# O robô do outro lado (AntiLaco) devolve :laco, e o executor para a execução nesta conversa. Sem teto de uso.
class Autonomia::Automacao::PassoDeMensagem
  include ::Autonomia::Automacao::NaConversa

  def executar
    return sem_conversa if @conversa.nil?

    negado = sem_acesso
    return negado if negado

    texto = texto_pronto
    return faltou_valor if texto.nil?

    mandar(texto)
  end

  # Com o texto já pronto. O "escrever" da F7 (#2500) chega aqui com o texto da IA.
  def mandar(texto)
    motivo = motivo_do_canal
    # Fora da janela o modelo sai no lugar do texto, que nem é lido: texto vazio não o impede.
    return mandar_modelo if motivo == 'fora_da_janela' && @passo['modelo']
    return pulado(motivo) if motivo
    return pulado('texto_vazio') if texto.strip.empty?

    anti_laco = ::Autonomia::Automacao::AntiLaco.new(@execucao.automacao, @conversa)
    return parar_por_robo(anti_laco) if anti_laco.robo_do_outro_lado?

    mensagem = ::Messages::MessageBuilder.new(nil, @conversa, content: texto, private: false, content_attributes: marca).perform
    Resultado.new(tipo: :ok, dados: { 'mensagem_id' => mensagem.id })
  end

  # Janela fechada com modelo na receita. O contato que não recebe e o canal sem resposta já pularam antes; o anti-laço
  # vale igual. O corpo é o do modelo aprovado, com os valores que o dono da conta escolheu.
  def mandar_modelo
    return pulado('fora_da_janela') unless ::Autonomia::Automacao::ModeloWhatsapp.aplica?(@conversa)

    pronto = ::Autonomia::Automacao::ModeloWhatsapp.new(@passo['modelo'], @conversa, valores)
                                                   .preparar
    return pulado(pronto) if pronto.is_a?(String)

    anti_laco = ::Autonomia::Automacao::AntiLaco.new(@execucao.automacao, @conversa)
    return parar_por_robo(anti_laco) if anti_laco.robo_do_outro_lado?

    mensagem = ::Autonomia::LiteralMessageBuilder.new(
      nil, @conversa,
      ActionController::Parameters.new(content: pronto.conteudo, private: false, template_params: pronto.template_params,
                                       content_attributes: marca),
      literal_content: true, literal_template_params: true
    ).perform
    Resultado.new(tipo: :ok, dados: { 'mensagem_id' => mensagem.id, 'modelo' => @passo.dig('modelo', 'nome') })
  end

  # O que pula sem olhar o texto: o "escrever" confere antes de pagar a IA.
  def motivo_do_canal
    return 'contato_nao_recebe' if Contact.opted_out.exists?(id: @conversa.contact_id)
    return 'canal_sem_resposta' if @conversa.additional_attributes.to_h['type'] == 'tweet'

    return if janela_aberta?

    @conversa.inbox.channel_type == 'Channel::Api' ? 'limite_da_caixa' : 'fora_da_janela'
  end

  private

  def pulado(motivo) = Resultado.new(tipo: :pulado, motivo: motivo, dados: {})

  def janela_aberta?
    ::Conversations::MessageWindowService.new(@conversa, automatic: true).can_reply? || @conversa.whatsapp_api_reply?
  end

  # Não manda, e deixa a nota para a equipe ver o que aconteceu (menciona quem ligou).
  def parar_por_robo(anti_laco)
    anti_laco.avisar_parada(@execucao, @passo['id'])
    Resultado.new(tipo: :laco, motivo: 'laco_suspeito', dados: {})
  end
end
