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
      ferramentas_nativas: %w[cotar_seguro_viagem detalhes_da_cotacao gerar_proposta_seguro_viagem],
      prontas: %w[cep cpf],
      seguradora: 'universal',
      conversa: CONVERSA_DO_PR1.merge('humanize_delivery' => true, 'voice_reply' => true)
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

  def disponiveis(account)
    MODELOS.keys.select { |chave| disponivel?(account, chave) }
  end

  def disponivel?(account, chave)
    modelo = MODELOS[chave]
    return false if modelo.nil? || account.nil?

    account.feature_enabled?(modelo[:flag]) &&
      Autonomia::FerramentasProntas.ligada?(account) &&
      account.feature_enabled?(Autonomia::FerramentasProntas::FLAG_CONSULTAS) &&
      Chatwoot.encryption_configured?
  end

  # -> os slugs das ferramentas nativas do modelo; nil para quem não é contratado.
  def ferramentas(agent)
    modelo(agent)&.fetch(:ferramentas_nativas)
  end
end
