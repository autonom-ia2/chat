# O MAPA DE UM LOCAL PRESENCIAL DA PÁGINA DE AGENDAMENTO (#1479 F3), numa mensagem própria logo depois da resposta.
#
# Síncrona e sem efeito na hora: marca o cartão no contexto do turno (`Delivery#marcar_cartao`); quem manda é o
# Responder, depois do texto. Chamada duas vezes, um cartão só. Sem contexto de entrega (Testar, Copiloto), o erro
# nomeado `cartao_sem_conversa`: a ferramenta continua no catálogo, como as assíncronas, para o Testar não mentir.
#
# Só entra no turno quando a página tem local presencial com endereço e coordenada (`CartaoDaPagina.locais`). Com um,
# não tem parâmetro. Com mais de um, `local_id` é obrigatório, numa lista fechada (enum), e a descrição lista os locais
# (rótulo e endereço) para o modelo escolher pelo que o cliente disse. Id fora da lista: recusa em texto, com a lista.
class Autonomia::Agents::Tools::Native::EnviarLocalizacao < Autonomia::Agents::Tools::Native::Base
  DESCRICAO = 'Manda ao cliente o mapa do endereço presencial deste atendimento, numa mensagem própria logo depois da ' \
              'sua resposta. Use quando o cliente perguntar onde fica, pedir o endereço ou a localização para ir até lá.'.freeze
  SEM_LOCAL = 'Esta página de agendamento não tem endereço com mapa agora. Diga o endereço por escrito, se ele estiver ' \
              'nas suas instruções; senão, passe para uma pessoa da equipe.'.freeze

  class << self
    def slug
      'enviar_localizacao'
    end

    def tool_name
      'Enviar localização'
    end

    def description
      DESCRICAO
    end

    def args_registraveis
      %w[local_id]
    end

    def available_for?(agent)
      locais_de(agent).any?
    end

    # Um local: sem parâmetro. Mais de um: o `local_id`, numa lista fechada, com os locais na descrição. `lista` não vai
    # ao schema (`propriedade` só leva tipo, descrição e enum): é de onde `description_for` tira os locais.
    def params_for(agent, **)
      locais = agent ? locais_de(agent) : []
      return [] if locais.size < 2

      [{ 'name' => 'local_id', 'type' => 'string', 'enum' => locais.pluck('id'), 'lista' => lista(locais),
         'description' => 'O id do local que o cliente quer, da lista na descrição da ferramenta.' }]
    end

    def description_for(parametros)
      local = parametros.find { |param| param['name'] == 'local_id' }
      local ? "#{DESCRICAO} Locais (local_id: rótulo — endereço): #{local['lista']}." : DESCRICAO
    end

    def locais_de(agent)
      ::Autonomia::Agents::Tools::Native::CartaoDaPagina.locais(::Autonomia::Agents::Tools::Native::CartaoDaPagina.pagina(agent))
    end

    def lista(locais)
      locais.map { |local| "#{local['id']}: #{local['rotulo']} — #{local['endereco']}" }.join('; ')
    end
  end

  def call
    return error('cartao_sem_conversa') if delivery.nil?

    locais = self.class.locais_de(agent)
    return recusar('cartao_sem_dado', SEM_LOCAL) if locais.empty?

    local = escolhido(locais)
    return recusar('cartao_local_invalido', local_invalido(locais)) if local.nil?

    delivery.marcar_cartao(::Autonomia::Agents::Tools::Native::CartaoDaPagina.cartao('location', local['id'], local['rich_message']))
    "O mapa de #{local['rotulo']} sai numa mensagem própria logo depois da sua resposta. Responda normalmente e não " \
      'escreva coordenadas nem link de mapa.'
  end

  private

  # Um local só: ele, com ou sem `local_id`. Mais de um: o do `local_id`, ou nil.
  def escolhido(locais)
    return locais.first if locais.one?

    locais.find { |local| local['id'] == params['local_id'].to_s }
  end

  def local_invalido(locais)
    "Escolha o local_id de um destes locais e chame de novo: #{self.class.lista(locais)}. Se o cliente não disse qual, " \
      'pergunte antes.'
  end
end
