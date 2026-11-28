# CATÁLOGO DOS AGENTES CONTRATADOS (#3211): modelos de agente que a Autonom.ia mantém e a conta apenas contrata
# (nome do agente, nome e apresentação da corretora). Cada modelo é uma entrada de `MODELOS`; o agente guarda a marca
# em `config['contratado']` e a instrução é montada a cada turno por `Contratados::Instrucao`, do arquivo da pasta do
# modelo, para o deploy seguinte valer sem tocar nos agentes já criados.
module Autonomia::Agents::Contratados
  MARCA = 'contratado'.freeze
  # A chave do `config` com a versão da base semeada (gravada ao contratar; reservada na API).
  BASE_VERSAO = 'contratado_base_versao'.freeze

  # O que a conversa do WhatsApp pede do PR 1 (espera a fala, fila, entrega inteira, ritmo do canal). Este PR só
  # GRAVA as quatro chaves no `config` do agente; quem as lê é o PR 1, então nada daqui chama código dele.
  CONVERSA_DO_PR1 = {
    'conversa_espera_a_fala' => true,
    'conversa_em_fila' => true,
    'conversa_entrega_inteira' => true,
    'conversa_ritmo_do_canal' => true
  }.freeze

  MODELOS = {
    'seguro_viagem_universal' => {
      flag: 'agente_seguro_viagem_universal',
      agent_type: 'sdr',
      pasta: Pathname.new(__dir__).join('contratados', 'seguro_viagem_universal'),
      arquivo: 'instrucao.md',
      ferramentas_nativas: %w[cotar_seguro_viagem detalhes_da_cotacao gerar_proposta_seguro_viagem situacao_do_pagamento
                              segunda_via_do_voucher coberturas_dos_planos],
      prontas: %w[cep cpf],
      seguradora: 'universal',
      # Para quem o modelo existe (#3269): a conta do nicho seguros com perfil corretora. Cada modelo diz o seu.
      segmento: { nicho: Autonomia::Agents::Nicho::SEGUROS, perfil: 'corretora' }.freeze,
      conversa: CONVERSA_DO_PR1.merge('humanize_delivery' => true, 'voice_reply' => true),
      # O preço (#3270): os dias grátis contam da primeira contratação do modelo na conta (`Contratados::Gratis`); depois,
      # o valor mensal vai na fatura da Hub2You. O único lugar desses números: a tela os recebe da API.
      dias_gratis: 7,
      preco_mensal_centavos: 19_700,
      moeda: 'BRL'
    }.freeze
  }.freeze

  # Marca presente e incompleta: o erro leva só o NOME do campo (nunca o valor), como o da Lia.
  class DadosIncompletos < Autonomia::Insurance::QuoteAgent::Builder::EscolhasIncompletas; end

  module_function

  def marca(agent)
    marca = agent&.config.to_h[MARCA]
    marca.is_a?(Hash) ? marca : nil
  end

  # -> o modelo do catálogo, ou nil (quem não é contratado, ou marca com modelo que o catálogo não tem).
  def modelo(agent)
    MODELOS[marca(agent)&.dig('modelo')]
  end

  # O catálogo da tela lista o modelo LIBERADO, mesmo sem a chave de IA da conta: quem clica em "Contratar" recebe a
  # recusa `sem_chave_de_ia`, que diz o que falta e onde resolver, em vez de um cartão que some sem explicação.
  def disponiveis(account)
    MODELOS.keys.select { |chave| liberado?(account, chave) }
  end

  # O segmento da conta (nicho E perfil) é o que o modelo pede? Conta sem escolha vale o padrão da instalação, que
  # `Nicho.for` já devolve (o mesmo critério de `Carteira::Acesso.liberada?`, que compara só o nicho).
  def segmento_certo?(account, modelo)
    escolha = Autonomia::Agents::Nicho.for(account)
    escolha.nicho == modelo[:segmento][:nicho] && escolha.perfil == modelo[:segmento][:perfil]
  end

  # O segmento do modelo, a flag, as duas das prontas e o cofre: o modelo existe para esta conta.
  def liberado?(account, chave)
    modelo = MODELOS[chave]
    return false if modelo.nil? || account.nil?

    segmento_certo?(account, modelo) &&
      account.feature_enabled?(modelo[:flag]) &&
      Autonomia::FerramentasProntas.ligada?(account) &&
      account.feature_enabled?(Autonomia::FerramentasProntas::FLAG_CONSULTAS) &&
      Chatwoot.encryption_configured?
  end

  # Liberado E com a chave de IA da PRÓPRIA conta (`Base.chave_da_conta`). O contratado conversa, busca na base e fala
  # por áudio com a chave da conta; a da instalação nunca paga o atendimento de um cliente (regra do Rodrigo, #3204).
  def disponivel?(account, chave)
    liberado?(account, chave) && Autonomia::Agents::Contratados::Base.chave_da_conta(account).present?
  end

  # -> os slugs das ferramentas nativas do modelo; nil para quem não é contratado.
  def ferramentas(agent)
    modelo(agent)&.fetch(:ferramentas_nativas)
  end
end
