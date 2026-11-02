# O passo "mensagem" (#2414 F4): manda texto ao cliente na conversa alvo. Sai como "Automação" (D9): sem remetente,
# com a marca da automação (`automacao_id`), que a lista única de envios automáticos reconhece
# (Autonomia::Agents::Operate::PessoaDaEquipe). O cliente recebe uma mensagem normal da empresa.
#
# Pula, com o motivo no registro:
# - valor vazio ou texto que ficou em branco;
# - contato que pediu para não receber (o mesmo campo das campanhas);
# - canal sem resposta (tweet);
# - janela fechada. Vale para todo canal com janela, lida como envio automático (sem a tag de agente humano da Meta,
#   24 h). Só texto livre: o modelo da Meta é a F4b, #2468. A caixa híbrida com o WhatsApp API pronto responde fora
#   da janela.
# O robô do outro lado (AntiLaco) devolve :laco, e o executor para a execução nesta conversa. Sem teto de uso.
class Autonomia::Automacao::PassoDeMensagem
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado

  def initialize(execucao:, passo:, valores:, conversa:)
    @execucao = execucao
    @passo = passo
    @valores = valores
    @conversa = conversa
  end

  def executar
    texto = ::Autonomia::Automacao::Texto.new(@passo['texto'], @valores).montar
    motivo = motivo_para_pular(texto)
    return Resultado.new(tipo: :pulado, motivo: motivo, dados: {}) if motivo

    anti_laco = ::Autonomia::Automacao::AntiLaco.new(@execucao.automacao, @conversa)
    return parar_por_robo(anti_laco) if anti_laco.robo_do_outro_lado?

    mensagem = ::Messages::MessageBuilder.new(nil, @conversa, content: texto, private: false, content_attributes: marca).perform
    Resultado.new(tipo: :ok, dados: { 'mensagem_id' => mensagem.id })
  end

  private

  def motivo_para_pular(texto)
    return 'faltou_valor' if texto.nil?
    return 'texto_vazio' if texto.strip.empty?
    return 'contato_nao_recebe' if Contact.opted_out.exists?(id: @conversa.contact_id)
    return 'canal_sem_resposta' if @conversa.additional_attributes.to_h['type'] == 'tweet'

    'fora_da_janela' unless janela_aberta?
  end

  def janela_aberta?
    ::Conversations::MessageWindowService.new(@conversa, automatic: true).can_reply? || @conversa.whatsapp_api_reply?
  end

  # Não manda, e deixa a nota para a equipe ver o que aconteceu (menciona quem ligou).
  def parar_por_robo(anti_laco)
    anti_laco.avisar_parada(@execucao, @passo['id'])
    Resultado.new(tipo: :laco, motivo: 'laco_suspeito', dados: {})
  end

  def marca
    { automacao_id: @execucao.automacao_id, execucao_id: @execucao.id, passo: @passo['id'] }
  end
end
