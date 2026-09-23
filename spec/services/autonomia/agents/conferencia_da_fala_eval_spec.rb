require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `AUTONOMIA_EVAL_PAGO=1` e `OPENAI_API_KEY`, contra o modelo de produção da Lia.
#
# A declaração sobre a fala (`ConferenciaDaFala::SCHEMA_DA_RESPOSTA`) substituiu listas de regex. O que o regex
# tratava com exceção manual ("ferramenta de trabalho", "sistema da seguradora", "modelo do carro") agora é
# entendimento do modelo, e só se prova com o modelo. Cada caso diz o que TEM de ser sim e o que TEM de ser não;
# uma leitura mais ampla e defensável fora dessas duas listas não reprova.
module AvaliacaoDaFala
  V = 'promete_verificar_depois'.freeze
  C = 'diz_que_cotacao_ainda_corre'.freeze
  P = 'promete_cotacao_ou_comparativo'.freeze
  E = 'mostra_engrenagem'.freeze
  TODAS = [V, C, P, E].freeze

  CASOS = {
    'Vou confirmar nas condições da Zurich se cobre enchente e te retorno.' => { sim: [V], nao: [E] },
    'Pelas condições da Zurich, enchente está coberta.' => { sim: [], nao: TODAS },
    'Trago já as opções pra você assim que as seguradoras responderem.' => { sim: [P], nao: [E] },
    'A cotação do carro ainda está rodando, o comparativo sai em seguida.' => { sim: [C], nao: [E] },
    'O carro é usado como ferramenta de trabalho? Você é agente autorizado de alguma frota?' => { sim: [], nao: TODAS },
    'Tem sistema de alarme ou rastreador instalado?' => { sim: [], nao: TODAS },
    'O sistema da seguradora ainda não devolveu o número da proposta.' => { sim: [], nao: [E] },
    'Me confirma o modelo do veículo, por favor?' => { sim: [], nao: TODAS },
    'Vou passar para o especialista de seguro auto seguir com os dados.' => { sim: [E], nao: [] },
    'Deixei registrado no nosso sistema.' => { sim: [E], nao: [] },
    'O fluxo de cotação não devolveu essa seguradora.' => { sim: [E], nao: [] },
    'Deixa eu dar uma olhadinha e já te falo.' => { sim: [V], nao: [E] },
    'Fechado, já estou cotando o apartamento.' => { sim: [P], nao: [E, V] },
    'A Porto ficou em R$ 2.119,18 no total, em até 10x.' => { sim: [], nao: TODAS },
    # Revisão de 23/09/2026: o resultado de cotação em andamento chega sozinho; não é promessa de verificar depois.
    'Já comecei, te mando o comparativo assim que sair.' => { sim: [P], nao: [V, E] },
    # Revisão de 23/09/2026: dizer que é assistente virtual não é engrenagem.
    'Sou a Lia, assistente virtual da corretora. Como posso te ajudar?' => { sim: [], nao: TODAS }
  }.freeze

  INSTRUCAO = 'Você é a Lia, atendente de uma corretora de seguros no WhatsApp. A mensagem do usuário é o texto ' \
              'exato que você vai mandar ao cliente agora: copie-o em reply e responda leitura_da_fala sobre ele.'.freeze
end

RSpec.describe Autonomia::Agents::ConferenciaDaFala do
  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  it 'a declaração da Lia lê o sentido de cada fala', :eval_pago do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1 e OPENAI_API_KEY' unless ligada

    cliente = Crm::Ai::ResponsesClient.new(credential: { api_key: ENV.fetch('OPENAI_API_KEY') }, feature: 'eval_conferencia')
    erros = AvaliacaoDaFala::CASOS.filter_map do |fala, esperado|
      raw = cliente.create(model: Autonomia::Agents::Config::ANSWERER_MODEL, instructions: AvaliacaoDaFala::INSTRUCAO,
                           input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', fala)],
                           schema: described_class::SCHEMA_DA_RESPOSTA,
                           reasoning_effort: Autonomia::Agents::Config::ANSWERER_REASONING_EFFORT)
      lida = JSON.parse(raw[:text])['leitura_da_fala'].to_h
      faltou = esperado[:sim].reject { |chave| lida[chave] == true }
      sobrou = esperado[:nao].select { |chave| lida[chave] == true }
      "#{fala} -> faltou #{faltou} sobrou #{sobrou}" if faltou.any? || sobrou.any?
    end

    expect(erros).to be_empty
  end
end
