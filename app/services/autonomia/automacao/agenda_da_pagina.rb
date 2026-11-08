# O link da agenda de uma página escolhida na receita (G44, #2756): `{"$valor": "agenda.<id da página>"}`. O exemplo 20
# manda o link da reunião de implantação e, depois, o de um treinamento: duas páginas, e `card.link_da_agenda` dá uma só.
#
# Parecer da Funções (#2756):
# - A página é achada pelo escopo da conta (páginas novas, publicadas e com quem atenda: InvitePages#usable) ao salvar e
#   ao rodar. Apagada, despublicada, de outra conta ou com o agendamento desligado: vazio, e o passo pula com o motivo.
# - Ao salvar, quem salva (ou liga) precisa de `agendamento_view`, a régua da tela de páginas. A receita sem pessoa (o
#   catálogo, a conversão) não leva página: ela se escolhe na instalação.
# - Ao rodar, quem ligou precisa da mesma chave; sem ela, o motivo próprio `sem_acesso_agenda`.
# - Qual link: LinkDaAgenda.da_pagina (a página fixa dá o dela; a por pessoa, só o link próprio do responsável).
class Autonomia::Automacao::AgendaDaPagina
  PREFIXO = 'agenda.'.freeze
  PERMISSAO = 'agendamento_view'.freeze
  SEM_ACESSO = 'sem_acesso_agenda'.freeze

  class << self
    # "agenda.12" => 12. Só o id em número, escrito do jeito canônico; o resto não é caminho de agenda.
    def pagina_id(caminho)
      texto = caminho.to_s
      return unless texto.start_with?(PREFIXO)

      id = Integer(texto.delete_prefix(PREFIXO), exception: false)
      id if id&.positive? && texto == "#{PREFIXO}#{id}"
    end

    def caminho?(caminho) = !pagina_id(caminho).nil?

    # Para a Receita: nil quando o caminho não é de página (segue a conferência de sempre); senão as frases do problema,
    # vazio quando pode salvar. A página vale em qualquer alvo: o que conta é a página e quem salva.
    def problemas(id, caminho, conta:, account_user:)
      return unless caminho?(caminho)

      chave = problema_ao_salvar(caminho, conta: conta, account_user: account_user)
      chave ? [I18n.t("autonomia.automacao.receita.#{chave}", passo: id, caminho: caminho)] : []
    end

    # A chave da frase do problema ao salvar, ou nil.
    def problema_ao_salvar(caminho, conta:, account_user:)
      return :agenda_so_na_instalacao if account_user.nil?
      return :agenda_sem_permissao unless account_user.permission_granted?(PERMISSAO)
      return :agenda_desligada unless ::Crm::Config.booking_v2_enabled?(conta)

      :agenda_pagina_inexistente unless ::Autonomia::Automacao::LinkDaAgenda.pagina_usavel(conta, pagina_id(caminho))
    end

    # O link para o alvo do `contexto`, com as permissões de `account_user` (quem ligou; no ensaio, quem pede).
    def resultado(caminho, contexto:, account_user:)
      return ::Autonomia::Automacao::LinkDaAgenda::Resultado.new(url: nil, por: SEM_ACESSO) unless account_user&.permission_granted?(PERMISSAO)

      ::Autonomia::Automacao::LinkDaAgenda.da_pagina(contexto.conta, responsavel(contexto), pagina_id(caminho))
    end

    # O motivo do passo que ficou só sem o link: sem a permissão, o próprio; o resto, o do link da agenda (G12).
    def motivo(por) = por == SEM_ACESSO ? SEM_ACESSO : 'faltou_link_da_agenda'

    # O ensaio do texto que ficou sem um valor, como o motor: sem o link da agenda (`por` de Valores#falta_da_agenda),
    # o motivo próprio e o porquê; senão, faltou_valor.
    def do_vazio(por) = por ? [motivo(por), { por: por }] : ['faltou_valor']

    private

    # Quem cuida do alvo: o dono do card ou quem atende a conversa. O contato não tem.
    def responsavel(contexto) = contexto.card&.owner || contexto.conversa&.assignee
  end
end
