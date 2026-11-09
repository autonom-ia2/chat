# O passo "mensagem" (#2414 F4): manda texto ao cliente na conversa alvo. Sai como "Automação" (D9): sem remetente,
# com a marca da automação (`automacao_id`), que a lista única de envios automáticos reconhece
# (Autonomia::Agents::Operate::PessoaDaEquipe). O cliente recebe uma mensagem normal da empresa.
#
# Pula e segue, com o motivo no registro:
# - valor vazio ou texto que ficou em branco;
# - contato que pediu para não receber ou bloqueado (decisão 5: a regra das campanhas, RecusaDoContato);
# - canal sem resposta (tweet);
# - alvo sem conversa e sem a caixa da conversa nova na receita (`sem_conversa`); com ela (#2680), o passo abre a
#   conversa (ConversaNova), e pula sem abrir se o contato não tem telefone (`contato_sem_telefone`) ou não recebe.
# Para a execução, com o motivo no registro (#2573, Autonomia::Automacao::JanelaFechada):
# - janela fechada. Vale para todo canal com janela, lida como envio automático (sem a tag de agente humano da Meta,
#   24 h). A caixa híbrida com o WhatsApp API pronto responde fora da janela, em texto. No número oficial, com a janela
#   fechada e um modelo aprovado na receita (F4b, #2468), sai o modelo (Autonomia::Automacao::ModeloWhatsapp); sem
#   modelo, ou fora do número oficial, o motivo continua `fora_da_janela`;
# - limite de horas que o dono pôs na caixa do canal API (`agent_reply_time_window`), vencido: `limite_da_caixa`. Sem
#   esse limite, o canal API responde a qualquer hora.
# Com a janela fechada, o modelo que não pôde sair (fora da caixa, não aprovado, de propaganda, mudou, variável vazia) também
# para: nada saiu ao cliente. O resultado leva `janela: fechada`, que é o que o executor lê.
# O robô do outro lado (AntiLaco) devolve :laco, e o executor para a execução nesta conversa. Sem teto de uso.
class Autonomia::Automacao::PassoDeMensagem
  include ::Autonomia::Automacao::NaConversa

  MOTIVOS_DE_JANELA = %w[fora_da_janela limite_da_caixa].freeze

  # Também usado pelo "escrever", que confere o canal antes de pagar a IA.
  def self.pulado(motivo, janela_fechada: MOTIVOS_DE_JANELA.include?(motivo))
    Resultado.new(tipo: :pulado, motivo: motivo, dados: janela_fechada ? { 'janela' => 'fechada' } : {})
  end

  def executar
    return abrir_e_mandar if @conversa.nil?

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

    # Os valores do modelo com as permissões de quem ligou (#2597), como no texto.
    pronto = ::Autonomia::Automacao::ModeloWhatsapp.new(@passo['modelo'], @conversa, valores).preparar
    return modelo_nao_sai(pronto) if pronto.is_a?(String)

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
    recusa = ::Autonomia::Automacao::RecusaDoContato.motivo(@conversa.contact_id)
    return recusa if recusa
    return 'canal_sem_resposta' if @conversa.additional_attributes.to_h['type'] == 'tweet'

    return if janela_aberta?

    @conversa.inbox.channel_type == 'Channel::Api' ? 'limite_da_caixa' : 'fora_da_janela'
  end

  private

  def pulado(motivo, **) = self.class.pulado(motivo, **)

  # Quem não tem conversa (#2680): a receita escolheu a caixa (ConversaNova). Abre a conversa e manda, juntos; o que não
  # sai (janela fechada sem modelo, texto vazio, robô) desfaz a conversa, e nada fica vazio na caixa. No card sem
  # conversa principal, a aberta vira a principal dele, e o registro do passo diz isso.
  def abrir_e_mandar
    caixa = ::Autonomia::Automacao::ConversaNova.da_execucao(@execucao)
    contato = ::Autonomia::Automacao::Contexto.de(@alvo).contato
    return sem_conversa if caixa.nil? || contato.nil?
    return Resultado.new(tipo: :sem_acesso, motivo: 'quem_ligou_sem_acesso', dados: {}) unless comeca_conversa?(caixa)

    motivo = ::Autonomia::Automacao::ConversaNova.motivo_do_contato(caixa, contato)
    return pulado(motivo) if motivo

    texto = texto_pronto
    return faltou_valor if texto.nil?

    na_conversa_nova(caixa, contato, texto)
  end

  def na_conversa_nova(caixa, contato, texto)
    resultado = nil
    ActiveRecord::Base.transaction do
      @conversa = ::Autonomia::Automacao::ConversaNova.abrir(caixa, contato)
      resultado = mandar(texto)
      raise ActiveRecord::Rollback unless resultado.tipo == :ok

      resultado = Resultado.new(tipo: :ok, dados: resultado.dados.merge(conversa_aberta))
    end
    @conversa = nil unless resultado.tipo == :ok
    resultado
  end

  def conversa_aberta
    dados = { 'conversa_aberta' => @conversa.reload.display_id }
    return dados unless @alvo.is_a?(::Crm::Card) && @alvo.conversation_id.nil?

    @alvo.update!(conversation_id: @conversa.id)
    dados.merge('conversa_principal_do_card' => @alvo.id)
  end

  def comeca_conversa?(caixa)
    usuario = @execucao.automacao.ligada_por
    account_user = usuario && @execucao.account.account_users.find_by(user_id: usuario.id)
    account_user.present? && ::Autonomia::Automacao::Acesso.comeca_conversa?(account_user, caixa)
  end

  # O modelo que não sai para a execução, como a janela fechada (#2573). Sem o link da agenda (G12), o motivo próprio
  # e o porquê.
  def modelo_nao_sai(motivo)
    por = valores.falta_da_agenda if motivo == 'faltou_valor'
    return pulado(motivo, janela_fechada: true) unless por

    Resultado.new(tipo: :pulado, motivo: 'faltou_link_da_agenda', dados: { 'por' => por, 'janela' => 'fechada' })
  end

  def janela_aberta?
    ::Conversations::MessageWindowService.new(@conversa, automatic: true).can_reply? || @conversa.whatsapp_api_reply?
  end

  # Não manda, e deixa a nota para a equipe ver o que aconteceu (menciona quem ligou).
  def parar_por_robo(anti_laco)
    anti_laco.avisar_parada(@execucao, @passo['id'])
    Resultado.new(tipo: :laco, motivo: 'laco_suspeito', dados: {})
  end
end
