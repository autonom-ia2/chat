# O que a cotação da renovação manda ao segurado (E8, #2901), no molde do aviso do Agendamento
# (Crm::BookingV2::Notices::Delivery): o modelo aprovado da Finalidade ("Algo mudou?", a proposta) pela caixa do
# WhatsApp oficial que a conta escolheu, e o "O que mudou?" na sessão aberta pela resposta do segurado.
#
# Antes de cada modelo, nesta ordem, e nada sai se um deles falha (`NaoSaiu`, com o motivo):
# - `contato_recusou`: a recusa e o bloqueio relidos do banco agora (Contact.campaign_refusal_now) e a regra do envio fora
#   da janela para a categoria do modelo (EnvioForaDaJanela::Regras.impedimento_do_contato);
# - `sem_caixa`: a conta não escolheu caixa, ou a escolhida deixou de ser do WhatsApp oficial;
# - `sem_modelo`: o modelo da Finalidade não está aprovado nessa caixa (Whatsapp::Templates::Garantir, sem criar: mandar
#   o modelo à Meta é decisão de fora daqui);
# - `sem_telefone`: o contato não tem telefone para abrir conversa na caixa;
# - `sem_card` / `campo_vazio`: o card de renovação sumiu, ou uma variável do modelo ficaria vazia (o primeiro nome do
#   contato sem nome, por exemplo). A Meta recusaria o modelo com a variável vazia.
#
# A mensagem vai na conversa aberta do contato nessa caixa, ou numa conversa nova (ContactInbox + ConversationBuilder,
# como o aviso do Agendamento). A cotação NUNCA atribui responsável à conversa: quem responde depois é a Lia (se ela
# está na caixa e a conta escolheu "Lia responde") ou a equipe. Toda mensagem leva a marca da cotação em
# `content_attributes` (`carteira_renovacao: { apolice_id:, etapa: }`), que é por onde a resposta é casada
# (Carteira::CotacaoRespostaListener). O que sai sozinho vai sem remetente; o envio da proposta pelo clique no card vai
# com quem clicou. Nada do conteúdo vai para log.
class Carteira::Cotacao::Envio
  # Um envio que não saiu, com o motivo (o código da lista acima) na mensagem.
  class NaoSaiu < StandardError; end

  # user: quem clicou, no envio pela tela; nil no que sai sozinho.
  def initialize(apolice, config, user: nil)
    @apolice = apolice
    @config = config
    @user = user
  end

  # -> a mensagem do modelo da Finalidade, já na conversa.
  # topo: a mídia do topo do modelo (a proposta), ou um bloco que a monta a partir da caixa; nil sem topo.
  def modelo(finalidade, etapa, topo: nil)
    conferir!(finalidade)
    caixa = caixa!
    pronto = pronto!(caixa, finalidade)
    corpo = valores!(pronto)
    params = mensagem(etapa, conteudo(finalidade, corpo))
    topo = topo.call(caixa) if topo.respond_to?(:call)
    params[:template_params] = { name: pronto[:nome], language: pronto[:idioma],
                                 processed_params: { body: corpo, buttons: botoes(pronto), header: topo }.compact }
    mandar(conversa!(caixa), params, modelo: true)
  end

  # As mesmas conferências do envio do modelo, sem mandar nada: antes de cotar, porque proposta que não pode sair não se
  # paga (decisão D7). Levanta `NaoSaiu`.
  def conferir!(finalidade)
    conferir_contato!
    pronto = pronto!(caixa!, finalidade)
    recusar('contato_recusou') if Whatsapp::Templates::EnvioForaDaJanela::Regras.impedimento_do_contato(contato, pronto[:categoria])
  end

  # A conversa do contato na caixa escolhida (a aberta, ou uma nova): é nela que a cotação roda (decisão D5).
  def conversa
    conferir_contato!
    conversa!(caixa!)
  end

  # -> a mensagem de texto na sessão, na conversa em que o segurado respondeu (sem remetente).
  def texto(conversa, conteudo, etapa)
    Autonomia::LiteralMessageBuilder.new(nil, conversa, ActionController::Parameters.new(mensagem(etapa, conteudo)),
                                         literal_content: true).perform
  end

  private

  def contato
    @apolice.contact
  end

  def conferir_contato!
    recusar('contato_recusou') if Contact.campaign_refusal_now(contato.id)
    recusar('sem_telefone') if contato.phone_number.blank?
  end

  def caixa!
    caixa = @config.inbox
    recusar('sem_caixa') unless caixa && caixa.account_id == @apolice.account_id && Whatsapp::Templates::MetaClient.supported?(caixa)
    caixa
  end

  def pronto!(caixa, finalidade)
    pronto = Whatsapp::Templates::Garantir.call(inbox: caixa, finalidade: finalidade, criar: false)
    recusar('sem_modelo') unless pronto[:status] == :pronto
    pronto
  end

  # As variáveis do corpo pelo catálogo de campos do card de renovação (o primeiro nome do contato, o fim da vigência).
  def valores!(pronto)
    card = @apolice.crm_card
    recusar('sem_card') if card.nil?
    resolver = TemplateFields::Resolver.for_card(card)
    corpo = pronto[:campos].to_h.to_h { |numero, campo| [numero.to_s, resolver.value(campo).to_s] }
    recusar('campo_vazio') if corpo.values.any?(&:blank?)
    corpo
  end

  # Os botões de resposta rápida levam só o payload, alinhados pelo índice (Crm::BookingV2::Notices::TemplateFill).
  def botoes(pronto)
    lista = Array(pronto[:botoes]).sort_by { |botao| botao['indice'].to_i }
    lista.map { |botao| { 'type' => 'quick_reply', 'payload' => botao['payload'] } }.presence
  end

  # O que o painel mostra: o corpo do modelo com os valores no lugar (troca de texto, sem regex).
  def conteudo(finalidade, corpo)
    texto = Whatsapp::Templates::Finalidades.pronto(finalidade).texto
    corpo.reduce(texto) { |atual, (numero, valor)| atual.gsub("{{#{numero}}}") { valor } }
  end

  def mensagem(etapa, conteudo)
    marca = { Carteira::Cotacao::MARCA => { apolice_id: @apolice.id, etapa: etapa } }
    { content: conteudo, private: false, message_type: 'outgoing', content_attributes: marca }
  end

  def conversa!(caixa)
    Conversation.where(account_id: caixa.account_id, inbox_id: caixa.id, contact_id: contato.id, status: %i[open pending])
                .order(:id).last || abrir_conversa(caixa)
  end

  def abrir_conversa(caixa)
    contact_inbox = ContactInbox.find_by(contact_id: contato.id, inbox_id: caixa.id) ||
                    ContactInboxBuilder.new(contact: contato, inbox: caixa, source_id: nil).perform
    ConversationBuilder.new(params: ActionController::Parameters.new(status: 'open'), contact_inbox: contact_inbox).perform
  end

  def mandar(conversa, params, modelo:)
    parametros = ActionController::Parameters.new(params)
    return mandar_pela_pessoa(conversa, parametros, modelo) if @user

    Autonomia::LiteralMessageBuilder.new(nil, conversa, parametros, literal_content: true, literal_template_params: modelo).perform
  end

  # O clique de "Enviar" no card (Carteira::Cotacao::Proposta): quem clicou é o remetente.
  def mandar_pela_pessoa(conversa, parametros, modelo)
    Autonomia::LiteralMessageBuilder.new(@user, conversa, parametros, literal_content: true, literal_template_params: modelo).perform
  end

  def recusar(motivo)
    raise NaoSaiu, motivo
  end
end
