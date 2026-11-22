# O resultado de uma ação do Guia que a plataforma recusou (extraído de `Acoes` na #3117, que passou do teto de tamanho).
#
# O erro que volta é o da própria plataforma: é ele que diz a verdade sobre o que faltou ou o que não foi permitido.
# Quando não há motivo legível, a pessoa lê uma frase traduzida, em vez de um número de status HTTP. (Fora de 401/403 o
# motivo vai como a plataforma escreveu; o modelo o repassa em palavras claras, no idioma da pessoa.)
#
# #3117: desde que o Guia faz para quem não administra, a recusa por permissão é a mais comum. A pessoa lê a frase
# traduzida, nunca o "You are not authorized" da plataforma; o motivo cru vai só para o modelo, na dica.
class Autonomia::Guide::RecusaDaPlataforma
  # O que esta aplicação devolve quando a policy nega (`render_unauthorized` responde 401), e o 403 de quem nega na mão.
  SEM_PERMISSAO = %w[401 403].freeze

  # Recusas 401 que não são falta de permissão do perfil, com a frase do Guia para cada uma. O card de um funil que a
  # pessoa não cuida (`Crm::Access::CardGuard::FUNNEL_REQUIRED`) se resolve liberando o funil, não o perfil.
  CODIGOS = { 'crm.access.card_funnel_required' => 'autonomia.guide.card_funnel_required' }.freeze

  def initialize(acao, resposta)
    @acao = acao
    @resposta = resposta
  end

  def resultado
    return sem_permissao if SEM_PERMISSAO.include?(@resposta.codigo.to_s)

    ::Autonomia::Guide::Acoes::Resultado.new(ok: false, mensagem: motivo || I18n.t('autonomia.guide.failed'),
                                             dica: ::Autonomia::Guide::Formatos::Retorno.new(@acao, @resposta).dica)
  end

  private

  def sem_permissao
    chave = CODIGOS.fetch(motivo.to_s, 'autonomia.guide.not_permitted')
    ::Autonomia::Guide::Acoes::Resultado.new(ok: false, mensagem: I18n.t(chave), dica: ("A plataforma respondeu: #{motivo}" if motivo))
  end

  def motivo
    return @motivo if defined?(@motivo)

    @motivo = begin
      dados = JSON.parse(@resposta.corpo.to_s)
      texto_do(dados) if dados.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end
  end

  # `error` pode vir como texto ou como objeto (`{ error: { code:, message: } }`, no CRM): o motivo é sempre texto.
  def texto_do(dados)
    erro = dados['error'].is_a?(Hash) ? dados['error']['message'] || dados['error']['code'] : dados['error']
    (dados['message'] || erro || Array(dados['errors']).join(', ')).to_s.presence
  end
end
