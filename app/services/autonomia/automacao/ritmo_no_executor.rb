# O limite de mensagens por cliente e o horário de envio da conta (#3063, item 2) nos passos que mandam mensagem ao
# cliente por iniciativa da empresa. Combinado com a Automação Ultra em 19/11:
# - onde: "mensagem" e "email" (passo_nativo), o "escrever" que fala com o cliente (passo_de_ia, antes de pagar a IA) e a
#   primeira pergunta da reunião e da pesquisa. A pergunta que sai depois que o cliente respondeu ao modelo vem na
#   retomada, por outro caminho, e não passa aqui;
# - consulta antes, contagem depois: o porteiro só conta o passo que mandou de fato (`mensagem_id` no resultado);
# - resposta a quem está esperando não conta nem espera: a última mensagem pública da conversa onde o passo manda é do
#   cliente. Vale para qualquer gatilho e qualquer ponto da receita (a resposta da primeira rodada, o galho "a cada
#   mensagem" do "esperar até", a mensagem depois de "esperar a resposta", o "decidir" que leu a resposta). Decidido uma
#   vez por passo, antes de mandar: depois do envio a última passa a ser a da empresa. Sem conversa ainda (o e-mail que
#   abre uma conversa nova), não é resposta;
# - fora do limite ou do horário: a execução espera até a hora (sem contar tentativa) e o histórico diz por quê.
# - #3101: o "mensagem" e o "email" com `quando: melhor_horario` esperam também a hora em que o cliente costuma escrever
#   (Autonomia::MelhorHorario, no máximo 24 h), só na primeira passada: quem volta de uma espera (do ritmo ou do melhor
#   horário) não espera o melhor horário de novo. A resposta a quem está esperando sai na hora, como no limite.
module Autonomia::Automacao::RitmoNoExecutor
  PASSOS_QUE_PERGUNTAM_AO_CLIENTE = [::Autonomia::Automacao::PassosQueEsperam::REUNIAO,
                                     ::Autonomia::Automacao::PassosQueEsperam::PESQUISA].freeze
  ORIGEM_POR_PASSO = Hash.new('automacao_mensagem').merge('email' => 'automacao_email').freeze
  MOTIVO = 'adiado_pelo_ritmo'.freeze
  MOTIVO_DO_MELHOR_HORARIO = 'adiado_pelo_melhor_horario'.freeze
  MELHOR_HORARIO = 'melhor_horario'.freeze

  private

  # O envio de um passo pelo ritmo: no passo ao cliente, adiado nada roda; senão `envio` manda, a mensagem que saiu conta
  # (fora da resposta a quem está esperando), e o bloco segue com o resultado. Nos outros passos, só manda e segue.
  def pelo_ritmo(passo, envio)
    return yield(envio.call) unless ao_cliente?(passo)

    resposta = cliente_esperando_resposta?(passo)
    return if !resposta && adiado_pelo_ritmo?(passo)

    resultado = envio.call
    contar_no_ritmo(passo, resultado) unless resposta
    yield resultado
  end

  # true quando adiou: a rodada parou e o passo roda de novo na hora. Com o melhor horário, a espera mais longa vence.
  def adiado_pelo_ritmo?(passo)
    ate = ::Autonomia::RitmoDeEnvio::Porteiro.quando(account: @account, contact: contato_do_ritmo)
    melhor = melhor_horario_do_passo(passo)
    return adiar(passo, melhor, MOTIVO_DO_MELHOR_HORARIO) if melhor && (ate.nil? || melhor > ate)
    return false unless ate

    adiar(passo, ate, MOTIVO)
  end

  def adiar(passo, ate, motivo)
    registrar(passo['id'], 'ok', motivo, 'ate' => ate.iso8601)
    aguardar(passo, ate, registrar: false)
    true
  end

  # #3101: a hora do cliente, se o passo pede e ainda não esperou nesta passada.
  def melhor_horario_do_passo(passo)
    return nil unless passo['quando'] == MELHOR_HORARIO
    return nil if [MOTIVO, MOTIVO_DO_MELHOR_HORARIO].include?(ultimo_motivo(passo))

    ::Autonomia::MelhorHorario.proximo(account: @account, contact: contato_do_ritmo)
  end

  # O passo voltou da espera do ritmo, não de uma pergunta que saiu: o último registro dele é o do adiamento. A reunião e
  # a pesquisa perguntam de novo em vez de conferir a resposta.
  def voltou_do_ritmo?(passo)
    ultimo_motivo(passo) == MOTIVO
  end

  def ultimo_motivo(passo)
    ::Autonomia::Automacao::Registro.where(execucao: @execucao, passo: passo['id']).order(:id).last&.motivo
  end

  def contar_no_ritmo(passo, resultado)
    return if resultado.dados.to_h['mensagem_id'].blank?

    ::Autonomia::RitmoDeEnvio::Porteiro.contar!(account: @account, contact_id: contato_do_ritmo&.id,
                                                origem: ORIGEM_POR_PASSO[passo['tipo']])
  end

  # O passo manda mensagem ao cliente: "avisar", o resumo que avisa a equipe e a aprovação ficam fora.
  def ao_cliente?(passo)
    case passo['tipo']
    # #3100: o "Mandar cupom" é uma mensagem ao cliente por iniciativa da empresa.
    when 'mensagem', 'email', ::Autonomia::Automacao::PassoDeMandarCupom::TIPO, *PASSOS_QUE_PERGUNTAM_AO_CLIENTE then true
    when 'escrever' then ::Autonomia::Automacao::PassoDeEscrever.fala_com_gente?(passo)
    else false
    end
  end

  def contato_do_ritmo = contexto.contato

  # A última mensagem pública (do cliente ou da equipe, robô incluído) da conversa onde o passo manda é do cliente. O
  # balão automático da caixa (`template`: saudação, fora do horário, pedido de e-mail, pesquisa de satisfação) sai
  # sozinho logo depois que o cliente escreve e não responde nada: fica de fora, com a nota interna e a atividade. O
  # e-mail abre uma conversa nova: nunca é resposta.
  def cliente_esperando_resposta?(passo)
    return false if passo['tipo'] == 'email'

    conversa = contexto.conversa
    return false unless conversa

    ultima = conversa.messages.where(private: false, message_type: %w[incoming outgoing]).reorder(id: :desc).first
    ultima&.incoming? || false
  end
end
