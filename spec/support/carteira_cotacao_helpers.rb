# Cotação da renovação (E8, #2901): o que os specs da cotação repetem. Os dados são sempre fictícios, a Meta é falsa
# (nenhum modelo sai, nenhum arquivo sobe) e o portal é o conector falso (Autonomia::Insurance::Connector::Mock).
module CarteiraCotacaoHelpers
  # Uma caixa do WhatsApp oficial (Cloud API, com WABA) da conta.
  def caixa_oficial(conta, nome: 'WhatsApp oficial')
    canal = create(:channel_whatsapp, account: conta, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                                      message_templates: [],
                                      provider_config: { 'api_key' => 'chave-exemplo', 'phone_number_id' => 'numero-exemplo',
                                                         'business_account_id' => 'waba-exemplo' })
    canal.inbox.update!(name: nome)
    canal.inbox
  end

  # Os modelos das Finalidades aprovados na caixa, como a Meta os lista (o topo de arquivo com um exemplo fictício).
  def aprovar_modelos(caixa, *finalidades)
    modelos = finalidades.map do |finalidade|
      pronto = Whatsapp::Templates::Finalidades.pronto(finalidade)
      pronto.corpo(header_handle: ('h-exemplo' if pronto.topo)).deep_stringify_keys.merge('id' => "t-#{finalidade}", 'status' => 'APPROVED')
    end
    caixa.channel.update_columns(message_templates: modelos) # rubocop:disable Rails/SkipsModelValidations
  end

  # O Agente de Cotação da conta (a Lia).
  def agente_de_cotacao(conta)
    Autonomia::Agents::Agent.create!(account: conta, name: 'Lia Exemplo', agent_type: 'insurance_quote', status: :active, enabled: true,
                                     instruction: 'Cote.')
  end

  # A conta com a chave da cotação e os ajustes da renovação: o funil, a caixa e as escolhas.
  def cotacao_ligada(conta, user:, caixa:, **escolhas)
    Carteira::Cotacao::Liberada.ligar!(conta)
    escolher_funil_de_renovacao(conta, user: user, inbox: caixa, quem_cota: 'robo', quem_envia: 'pessoa', **escolhas)
  end

  # A mensagem do "Algo mudou?" que a cotação mandou para o seguro.
  def algo_mudou_de(apolice)
    Message.where(account_id: apolice.account_id).order(:id).find do |mensagem|
      Carteira::Cotacao.marca_de(mensagem) == { 'apolice_id' => apolice.id, 'etapa' => 'algo_mudou' }
    end
  end

  # O toque do segurado num botão do "Algo mudou?" (como o RichMessages::SelectedOption grava).
  def tocar(mensagem, payload, titulo: 'Nada mudou')
    mensagem.conversation.messages.create!(account_id: mensagem.account_id, inbox_id: mensagem.inbox_id, message_type: :incoming,
                                           sender: mensagem.conversation.contact, content: titulo,
                                           content_attributes: { 'selected_option' => { 'id' => payload, 'title' => titulo },
                                                                 'in_reply_to' => mensagem.id })
  end

  def tipos_da_historia(apolice)
    apolice.eventos.reload.order(:quando, :id).pluck(:tipo)
  end
end

RSpec.configure do |config|
  config.include CarteiraCotacaoHelpers
end
