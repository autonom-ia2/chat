# O CARTÃO DE CONTATO DA PÁGINA DE AGENDAMENTO (#1479 F3), numa mensagem própria logo depois da resposta.
#
# Manda SÓ o `contact_phone` da página, com o título dela (ou o nome público) como nome do cartão
# (`CartaoDaPagina.contato`); nunca o telefone de uma pessoa da equipe. Como `enviar_localizacao`: marca o cartão no
# contexto do turno, um só por turno, e sem contexto de entrega devolve o erro nomeado `cartao_sem_conversa`. Só entra
# no turno quando o telefone da página serve para o cartão ("+" e 8 a 15 dígitos).
class Autonomia::Agents::Tools::Native::EnviarContato < Autonomia::Agents::Tools::Native::Base
  SEM_TELEFONE = 'Esta página de agendamento não tem telefone de contato agora. Não invente um número; se o cliente ' \
                 'precisar falar por telefone, passe para uma pessoa da equipe.'.freeze

  class << self
    def slug
      'enviar_contato'
    end

    def tool_name
      'Enviar contato'
    end

    def description
      'Manda ao cliente o cartão com o telefone de contato deste atendimento, numa mensagem própria logo depois da sua ' \
        'resposta, para ele salvar ou ligar. Use quando o cliente pedir um telefone ou um contato.'
    end

    def available_for?(agent)
      contato_de(agent).present?
    end

    def contato_de(agent)
      ::Autonomia::Agents::Tools::Native::CartaoDaPagina.contato(::Autonomia::Agents::Tools::Native::CartaoDaPagina.pagina(agent))
    end
  end

  def call
    return error('cartao_sem_conversa') if delivery.nil?

    formato = self.class.contato_de(agent)
    return recusar('cartao_sem_dado', SEM_TELEFONE) if formato.nil?

    chave = ::Autonomia::Agents::Tools::Native::CartaoDaPagina::CHAVE_DO_CONTATO
    delivery.marcar_cartao(::Autonomia::Agents::Tools::Native::CartaoDaPagina.cartao('contact', chave, formato))
    'O cartão de contato sai numa mensagem própria logo depois da sua resposta. Responda normalmente e não escreva o ' \
      'número de novo.'
  end
end
