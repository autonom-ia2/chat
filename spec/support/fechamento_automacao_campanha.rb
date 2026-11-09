# As sondas da G37 e da G38 (lote 5, #2686), por comportamento: cada uma monta o cenário mínimo, roda o código da
# campanha e confere o efeito, em vez de perguntar se um campo ou um valor existe. Rodam na transação do exemplo, que
# desfaz tudo. Ficam fora de FechamentoAutomacao::Lacunas, que já está no teto de linhas do módulo.
module FechamentoAutomacao::SondasDaCampanha
  extend WebMock::API

  module_function

  PRE_BLACK = { 'name' => 'pre_black', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
                'components' => [{ 'type' => 'BODY', 'text' => 'Oi! A Black começa {{1}}.' }] }.freeze
  FILTRO_PRE_BLACK = { 'campo' => { '$valor' => 'mensagem.campanha' }, 'op' => 'igual', 'valor' => 'Pré-Black' }.freeze

  # G37 (exemplo 7, passo 2): o passo campanha monta "a mesma campanha para todos os outros contatos", e o envio deixa
  # de fora quem tem a etiqueta excluída e quem pediu para não receber. O envio para no método que fala com a Meta, que
  # só anota o número.
  def campanha_para_todos_os_outros?
    canal = caixa_oficial
    account = canal.account
    ja_comprou = FactoryBot.create(:label, account: account, title: 'ja_comprou')
    outro = FactoryBot.create(:contact, account: account, phone_number: '+5511900000371')
    FactoryBot.create(:contact, account: account, phone_number: '+5511900000372').update_labels(['ja_comprou'])
    FactoryBot.create(:contact, account: account, phone_number: '+5511900000373').opt_out!(source: 'manual')
    campanha = campanha_do_passo(account, canal.inbox, ja_comprou)
    campanha.present? && enviados_por(campanha) == [outro.phone_number]
  end

  # G38 (exemplo 7, passo 3): o filtro "respondeu à campanha Pré-Black" do gatilho da mensagem, avaliado como a Partida
  # avalia, casa com a resposta de quem recebeu a Pré-Black e não com a de quem recebeu outra campanha.
  def filtro_da_campanha_filtra?
    return false unless defined?(::CampaignRecipient)

    canal = FactoryBot.create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    casou = %w[Pré-Black Outra].map do |titulo|
      conversa, mensagem = resposta_a(canal, titulo)
      valores = Autonomia::Automacao::Valores.new(alvo: conversa, mensagem: mensagem, quem: nil)
      Autonomia::Automacao::Condicao.new(FILTRO_PRE_BLACK, valores).verdadeira?
    end
    casou == [true, false]
  end

  def caixa_oficial
    canal = FactoryBot.create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    canal.update!(message_templates: [PRE_BLACK])
    canal.account.enable_features!('whatsapp_campaign')
    canal
  end

  def campanha_do_passo(account, caixa, excluida)
    dona = FactoryBot.create(:user, account: account, role: :administrator)
    automacao = FactoryBot.create(:autonomia_automacao, account: account, ligada_por: dona)
    passo = { 'id' => 'c2', 'tipo' => 'campanha', 'faz' => 'disparar', 'titulo' => 'Pré-Black', 'caixa_id' => caixa.id,
              'publico' => 'todos', 'sem_etiquetas' => [excluida.id],
              'modelo' => { 'nome' => 'pre_black', 'idioma' => 'pt_BR', 'variaveis' => [['sexta']] } }
    execucao = Autonomia::Automacao::Execucao.new(automacao: automacao, account: account)
    resultado = Autonomia::Automacao::PassoDeCampanha.new(execucao: execucao, passo: passo, alvo: account).executar
    account.campaigns.find_by(display_id: resultado.dados['campanha_id']) if resultado.tipo == :ok
  end

  # O disparo de verdade (Whatsapp::OneoffCampaignService, com o overlay do EE e a jornada), parado só na chamada à Meta.
  # A conferência do modelo no disparo (#1329) cai na lista guardada da caixa.
  def enviados_por(campanha)
    stub_request(:get, WhatsappTemplateLookupHelpers::TEMPLATE_LOOKUP).to_return(status: 503)
    enviados = []
    envio = Whatsapp::OneoffCampaignService.new(campaign: campanha)
    envio.define_singleton_method(:send_whatsapp_template_message) { |to:, **| enviados << to }
    envio.perform
    enviados
  end

  def resposta_a(canal, titulo)
    account = canal.account
    contato = FactoryBot.create(:contact, account: account)
    campanha = FactoryBot.create(:campaign, account: account, inbox: canal.inbox, title: titulo)
    CampaignRecipient.create!(account: account, campaign: campanha, contact: contato, inbox: canal.inbox, status: :sent,
                              sent_at: 1.hour.ago)
    conversa = FactoryBot.create(:conversation, account: account, inbox: canal.inbox, contact: contato)
    [conversa, FactoryBot.create(:message, account: account, inbox: canal.inbox, conversation: conversa, message_type: :incoming)]
  end
end
