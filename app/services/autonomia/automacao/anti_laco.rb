# Proteção contra laço do passo "mensagem" (#2414 F4). Não é teto de uso: a regra do Rodrigo (31/10/2026) é sem freio
# no uso do cliente. Tudo aqui pega defeito, e o uso legítimo, por maior que seja, passa.
#
# Duas camadas:
# 1. A cadeia comum (F1, D6) não é daqui: a mensagem sai dentro da cadeia da execução, e a escuta não dispara a
#    própria automação nem passa da profundidade 3.
# 2. Robô do outro lado, que a cadeia não vê (decisões da sessão Automação, 02/11). Conta os envios respondidos: cada
#    mensagem do passo "mensagem" do motor novo que recebe resposta do contato em menos de RESPOSTA_DE_ROBO soma 1. Com
#    TROCAS_DO_ROBO envios respondidos seguidos desde o último corte, a execução para nesta conversa. O corte é uma
#    pessoa da equipe escrevendo ou a conversa CONVERSA_PARADA sem mensagem; resposta lenta zera a conta. Mensagem de
#    IA, de robô (AgentBot), das automações antigas ou de campanha fica de fora: não conta nem corta.
#    Contar envios, e não trocas, pega a amplificação: o robô que responde com 2 balões dispara uma execução por balão,
#    o volume dobra a cada volta e a contagem chega a 40 em poucas voltas. Gente não responde 40 vezes em menos de 20
#    segundos sem pausa de meia hora; o cliente que manda muitas mensagens no próprio ritmo, ou erra o menu, passa.
#
# Não há camada de "texto repetido": responder o mesmo texto a cada mensagem do cliente é uso (o menu "responda 1 ou
# 2"). A duplicidade de verdade é o mesmo evento chegando duas vezes, e quem a trata é a escuta, pelo evento.
class Autonomia::Automacao::AntiLaco
  TROCAS_DO_ROBO = 40
  RESPOSTA_DE_ROBO = 20.seconds
  CONVERSA_PARADA = 30.minutes
  # Limite técnico da consulta, não teto de uso: passar dele não dispara nada. O laço bate as 40 muito antes.
  LEITURA = 1000
  # A marca da nota da parada, para não repetir a nota até o próximo corte.
  AVISO = 'laco'.freeze

  def initialize(definicao, conversa)
    @definicao = definicao
    @conversa = conversa
  end

  def robo_do_outro_lado?
    envios_respondidos >= TROCAS_DO_ROBO
  end

  # A execução parou por robô do outro lado: fica uma nota na conversa para a equipe, que menciona quem ligou (se ela
  # ainda enxerga a conversa). Uma nota só por automação e conversa até o próximo corte: o robô de 2 balões deixa várias
  # execuções em voo, e cada uma para aqui. A trava da conversa impede que duas criem a nota ao mesmo tempo.
  def avisar_parada(execucao, passo_id)
    @conversa.with_lock do
      next if ja_avisou?

      marca = { automacao_id: @definicao.id, execucao_id: execucao.id, passo: passo_id, aviso: AVISO }
      ::Autonomia::Automacao::Nota.criar(conversa: @conversa, texto: texto_da_parada, pessoas: quem_ligou, marca: marca)
    end
  end

  private

  # Já há nota de parada desta automação desde o último corte (a mesma janela da contagem).
  def ja_avisou?
    inicio = desde_o_ultimo_corte.first&.created_at
    return false if inicio.nil?

    @conversa.messages.where(private: true).where(created_at: inicio..).any? do |nota|
      atributos = nota.content_attributes.to_h
      atributos['aviso'] == AVISO && atributos['automacao_id'].to_i == @definicao.id
    end
  end

  def texto_da_parada
    I18n.with_locale(@conversa.account.locale) do
      I18n.t('autonomia.automacao.nota.laco', nome: @definicao.nome, trocas: TROCAS_DO_ROBO, segundos: RESPOSTA_DE_ROBO.to_i)
    end
  end

  def quem_ligou = ::Autonomia::Automacao::Nota.alcancaveis(@conversa, [@definicao.ligada_por_id])

  # Na ordem do tempo, desde o último corte: cada resposta do contato dá baixa nos nossos envios que esperavam e soma os
  # que ela pegou em menos de RESPOSTA_DE_ROBO. Envios seguidos: a resposta que chega em RESPOSTA_DE_ROBO ou mais
  # depois do nosso último envio zera a conta, como a pessoa da equipe. Robô não demora; gente demora, e a conversa
  # humana longa, sem pausa de meia hora, não junta respostas rápidas espalhadas. Envio ainda sem resposta não conta.
  def envios_respondidos
    esperando = []
    desde_o_ultimo_corte.reduce(0) do |conta, mensagem|
      if nosso?(mensagem)
        esperando << mensagem
        next conta
      end

      pegos = esperando
      esperando = []
      somar(conta, pegos, mensagem)
    end
  end

  def somar(conta, pegos, resposta)
    return conta if pegos.empty?
    return 0 if resposta.created_at - pegos.last.created_at >= RESPOSTA_DE_ROBO

    conta + pegos.count { |envio| resposta.created_at - envio.created_at < RESPOSTA_DE_ROBO }
  end

  # Da mais nova para trás, até o corte: pessoa da equipe, ou CONVERSA_PARADA sem mensagem (contando de agora até a
  # mais nova, e entre uma e a anterior). Devolve na ordem do tempo.
  def desde_o_ultimo_corte
    seguinte = Time.current
    contadas.take_while do |mensagem|
      continua = !pessoa?(mensagem) && seguinte - mensagem.created_at <= CONVERSA_PARADA
      seguinte = mensagem.created_at
      continua
    end.reverse
  end

  def contadas
    @conversa.messages.where(private: false, message_type: %i[incoming outgoing])
             .reorder(created_at: :desc, id: :desc).limit(LEITURA).to_a
             .select { |mensagem| mensagem.incoming? || nosso?(mensagem) || pessoa?(mensagem) }
  end

  def nosso?(mensagem)
    mensagem.outgoing? && mensagem.content_attributes.to_h['automacao_id'].present?
  end

  def pessoa?(mensagem)
    ::Autonomia::Agents::Operate::PessoaDaEquipe.da_pessoa?(mensagem)
  end
end
