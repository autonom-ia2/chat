# O Guia LEVANDO a pessoa até a tela (issue #590).
#
# O botão "ir para a tela" saía do fluxo do manual mais parecido com a pergunta,
# e o painel montava a rota só com o id da conta. Tela de UMA caixa, UMA
# conversa ou UM agente nunca tinha botão: a rota não fechava e ele sumia calado.
#
# Quem sabe qual caixa é o modelo — ele leu a conta. Aqui ele diz a tela e os
# ids, `Guide::Telas` confere contra o mapa, e o painel monta o botão. Não abre
# nada sozinha: a pessoa clica, e a guarda da rota aplica a permissão dela.
class Autonomia::Agents::Tools::Native::GuiaTela < Autonomia::Agents::Tools::Native::Base
  class << self
    def slug
      'mostrar_tela'
    end

    def description
      'Põe, abaixo da sua resposta, o botão que leva a pessoa até a tela certa. Use sempre que a ' \
        'resposta for "é lá em tal tela" — inclusive a tela de UM registro (uma caixa, uma conversa, ' \
        'um agente), com o id que você leu da conta. Não navega sozinha: a pessoa clica.'
    end

    def params
      [
        { 'name' => 'tela', 'type' => 'string',
          'description' => 'O nome da rota, exatamente como está no campo "rota" ou "nav_target" dos ' \
                           'fluxos que você recebeu (ex.: "settings_inbox_show").' },
        { 'name' => 'parametros_json', 'type' => 'string', 'required' => false,
          'description' => 'Preenche os ":" do endereço da rota, como objeto JSON, com os nomes do ' \
                           'endereço: para ".../inboxes/:inboxId/:tab?", {"inboxId":"12","tab":"business-hours"}. ' \
                           'O id da conta não precisa. Deixe vazio quando o endereço não tiver ":".' },
        { 'name' => 'destaque', 'type' => 'string', 'required' => false,
          'description' => 'O campo "highlight" do fluxo, quando houver: o elemento da tela que fica ' \
                           'em destaque depois do clique.' }
      ]
    end
  end

  def call
    return recusa_sem_contexto if @operador.nil?

    destino = telas.destino(@params['tela'], parametros, @params['destaque'],
                            permissoes: Array(@operador.account_user&.permissions))
    nao_lidos = @operador.nao_lidos(destino[:params])
    return sem_leitura(nao_lidos) if nao_lidos.any?

    @operador.mostrar(destino)
    "Pronto: o botão para a tela já aparece logo abaixo da sua resposta. Não escreva o endereço nem um link.#{registros}"
  rescue ::Autonomia::Guide::Telas::Recusada => e
    e.message
  end

  private

  def telas
    ::Autonomia::Guide::Telas.padrao
  end

  def sem_leitura(nao_lidos)
    "Não montei o botão: #{nao_lidos.map { |nome, valor| "#{nome} #{valor}" }.join(', ')} não veio de nenhuma " \
      'leitura da conta nesta conversa. Leia a conta para confirmar que o registro existe; se não existir, ' \
      'diga isso à pessoa.'
  end

  # Levou à lista, mas a pessoa pode ter falado de UM registro dela. O modelo
  # lê isto e, se for o caso, chama de novo com a tela do registro — vale a
  # última chamada.
  def registros
    abaixo = telas.de_um_registro(@params['tela'])
    return '' if abaixo.empty?

    " Se ela falou de UM registro específico, existe a tela dele: #{abaixo.join('; ')}. " \
      'Nesse caso, leia a conta para achar o id e chame de novo com essa tela.'
  end

  def parametros
    texto = @params['parametros_json'].to_s.strip
    return {} if texto.blank?

    valores = JSON.parse(texto)
    valores.is_a?(Hash) ? valores : {}
  rescue JSON::ParserError
    {}
  end

  def recusa_sem_contexto
    'Não consigo montar o botão agora porque não sei quem está perguntando. Diga o caminho pelo menu.'
  end
end
