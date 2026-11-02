# Proteção contra laço do passo "mensagem" (#2414 F4). Não é teto de uso: a regra do Rodrigo (31/10/2026) é sem freio
# no uso do cliente. Tudo aqui pega defeito, e o uso legítimo, por maior que seja, passa.
#
# Duas camadas:
# 1. A cadeia comum (F1, D6) não é daqui: a mensagem sai dentro da cadeia da execução, e a escuta não dispara a
#    própria automação nem passa da profundidade 3.
# 2. Robô do outro lado, que a cadeia não vê (decisão da sessão Automação, 02/11). Uma troca é um envio do passo
#    "mensagem" do motor novo seguido da resposta do contato. O sinal é TROCAS_DO_ROBO trocas seguidas com a resposta
#    chegando em menos de RESPOSTA_DE_ROBO. Mensagem de IA, de robô (AgentBot), das automações antigas ou de campanha
#    fica de fora: não conta nem zera. Zera quando uma pessoa da equipe escreve ou quando a conversa fica CONVERSA_PARADA
#    sem mensagem. Gente não responde 20 vezes seguidas em menos de 20 segundos; o cliente que manda muitas mensagens
#    no próprio ritmo, ou erra o menu várias vezes, passa.
#
# Não há camada de "texto repetido": responder o mesmo texto a cada mensagem do cliente é uso (o menu "responda 1 ou
# 2"). A duplicidade de verdade é o mesmo evento chegando duas vezes, e quem a trata é a escuta, pelo evento.
class Autonomia::Automacao::AntiLaco
  TROCAS_DO_ROBO = 20
  RESPOSTA_DE_ROBO = 20.seconds
  CONVERSA_PARADA = 30.minutes
  # Quantas mensagens o cálculo lê: as trocas mais folga para o que fica de fora (IA, campanha) no meio.
  LEITURA = TROCAS_DO_ROBO * 4

  def initialize(definicao, conversa)
    @definicao = definicao
    @conversa = conversa
  end

  def robo_do_outro_lado?
    trocas_seguidas >= TROCAS_DO_ROBO
  end

  # A execução parou por robô do outro lado: fica uma nota na conversa para a equipe, que menciona quem ligou (se ela
  # ainda enxerga a conversa).
  def avisar_parada(execucao, passo_id)
    texto = I18n.with_locale(@conversa.account.locale) do
      I18n.t('autonomia.automacao.nota.laco', nome: @definicao.nome, trocas: TROCAS_DO_ROBO, segundos: RESPOSTA_DE_ROBO.to_i)
    end
    pessoas = ::Autonomia::Automacao::Nota.alcancaveis(@conversa, [@definicao.ligada_por_id])
    marca = { automacao_id: @definicao.id, execucao_id: execucao.id, passo: passo_id }
    ::Autonomia::Automacao::Nota.criar(conversa: @conversa, texto: texto, pessoas: pessoas, marca: marca)
  end

  private

  # Da mais nova para a mais velha, aos pares: a resposta do contato e o nosso envio logo antes dela. A contagem para
  # na primeira dupla que não é "resposta depressa a um envio nosso": pessoa da equipe, resposta lenta, conversa parada
  # entre uma troca e outra, ou dois seguidos do mesmo lado.
  def trocas_seguidas
    mensagens = contadas
    return 0 if mensagens.empty? || mensagens.first.created_at < CONVERSA_PARADA.ago

    trocas = 0
    envio_seguinte = nil
    mensagens.each_slice(2) do |resposta, envio|
      break unless troca?(resposta, envio)
      break if envio_seguinte && envio_seguinte.created_at - resposta.created_at > CONVERSA_PARADA

      trocas += 1
      envio_seguinte = envio
    end
    trocas
  end

  def contadas
    @conversa.messages.where(private: false, message_type: %i[incoming outgoing])
             .reorder(created_at: :desc, id: :desc).limit(LEITURA).to_a
             .select { |mensagem| mensagem.incoming? || nosso?(mensagem) || pessoa?(mensagem) }
  end

  def troca?(resposta, envio)
    envio.present? && resposta.incoming? && nosso?(envio) && resposta.created_at - envio.created_at < RESPOSTA_DE_ROBO
  end

  def nosso?(mensagem)
    mensagem.outgoing? && mensagem.content_attributes.to_h['automacao_id'].present?
  end

  def pessoa?(mensagem)
    ::Autonomia::Agents::Operate::PessoaDaEquipe.da_pessoa?(mensagem)
  end
end
