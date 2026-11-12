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
# O contato trocou de número (G43, #2700, NumeroNovo): no WhatsApp e no SMS a mensagem sai na conversa do número novo,
# na mesma caixa, aberta junto com o envio, com as mesmas regras abaixo. O registro diz `numero_novo`.
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
    return no_numero_novo(texto) if ::Autonomia::Automacao::NumeroNovo.trocou?(@conversa)

    mandar_aqui(texto)
  end

  # Na conversa que o passo já tem: a do alvo, a nova (#2680) ou a do número novo (G43).
  def mandar_aqui(texto)
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
    mandar_em(-> { ::Autonomia::Automacao::ConversaNova.abrir(caixa, contato) }, texto) { conversa_aberta(nil) }
  end

  # G43 (#2700): o telefone do contato mudou. Manda na conversa do número novo, na mesma caixa (NumeroNovo). Quem ligou
  # precisa poder começar conversa nela, como na conversa nova. No card, ela toma o lugar da principal antiga.
  def no_numero_novo(texto)
    antiga = @conversa
    return Resultado.new(tipo: :sem_acesso, motivo: 'quem_ligou_sem_acesso', dados: {}) unless comeca_conversa?(antiga.inbox)
    return pulado('numero_de_outro_contato') if ::Autonomia::Automacao::NumeroNovo.de_outro_contato?(antiga)

    mandar_em(-> { ::Autonomia::Automacao::NumeroNovo.conversa(antiga) }, texto) do
      conversa_aberta(antiga.id).merge('numero_novo' => true)
    end
  end

  # Abre (ou reaproveita) a conversa e manda, juntos: o que não sai (janela fechada sem modelo, texto vazio, robô,
  # contato que não recebe) desfaz a conversa aberta, e nada fica vazio na caixa. O bloco diz o que vai ao registro.
  def mandar_em(abrir, texto)
    antes = @conversa
    resultado = nil
    ActiveRecord::Base.transaction do
      @conversa = abrir.call
      resultado = mandar_aqui(texto)
      raise ActiveRecord::Rollback unless resultado.tipo == :ok

      resultado = Resultado.new(tipo: :ok, dados: resultado.dados.merge(yield))
    end
    @conversa = antes unless resultado.tipo == :ok
    resultado
  end

  # `principal`: o id da conversa principal do card que a aberta substitui. O card sem conversa principal também a ganha.
  def conversa_aberta(principal)
    dados = { 'conversa_aberta' => @conversa.reload.display_id }
    return dados unless @alvo.is_a?(::Crm::Card) && [principal, nil].include?(@alvo.conversation_id)

    @alvo.update!(conversation_id: @conversa.id)
    dados.merge('conversa_principal_do_card' => @alvo.id)
  end

  def comeca_conversa?(caixa) = ::Autonomia::Automacao::Acesso.pessoa_comeca_conversa?(@execucao.dona.ligada_por, caixa)

  # O modelo que não sai para a execução, como a janela fechada (#2573). Sem o link da agenda (G12), o motivo próprio
  # e o porquê.
  def modelo_nao_sai(motivo)
    por = valores.falta_da_agenda if motivo == 'faltou_valor'
    return pulado(motivo, janela_fechada: true) unless por

    Resultado.new(tipo: :pulado, motivo: ::Autonomia::Automacao::LinkDaAgenda.motivo(por), dados: { 'por' => por, 'janela' => 'fechada' })
  end

  # A janela da conversa onde a mensagem vai sair. O "escrever" pergunta antes da IA, ainda na conversa do número antigo:
  # com o número trocado (G43), vale a do número novo, nas duas perguntas (a janela oficial e o WhatsApp API da caixa
  # híbrida), e a conversa que ainda vai ser aberta não tem mensagem do cliente.
  def janela_aberta?
    destino = conversa_do_envio
    ::Conversations::MessageWindowService.new(destino, automatic: true).can_reply? || destino.whatsapp_api_reply?
  end

  def conversa_do_envio
    return @conversa unless ::Autonomia::Automacao::NumeroNovo.trocou?(@conversa)

    ::Autonomia::Automacao::NumeroNovo.existente(@conversa) ||
      ::Conversation.new(account: @conversa.account, inbox: @conversa.inbox, contact: @conversa.contact)
  end

  # Não manda, e deixa a nota para a equipe ver o que aconteceu (menciona quem ligou).
  def parar_por_robo(anti_laco)
    anti_laco.avisar_parada(@execucao, @passo['id'])
    Resultado.new(tipo: :laco, motivo: 'laco_suspeito', dados: {})
  end
end
