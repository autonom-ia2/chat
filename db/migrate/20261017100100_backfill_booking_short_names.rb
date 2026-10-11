# Dados (#1299): dá endereço curto às páginas de agendamento novas que só tinham o link comprido. Separada da
# migration de esquema (20261017100000) de propósito: esta só grava linhas.
#
# O que grava, por conta que tem página nova (uma transação por conta):
# - uma linha em `crm_booking_account_addresses`, se a conta ainda não tem endereço (nome da conta sem acento, em
#   minúsculas, com número quando já tem dono);
# - `crm_agent_booking_profiles.short_name` das páginas novas (page_version 2) em que ele está vazio (título da página
#   sem acento, com número quando repete na conta);
# - o apelido (`metadata.short_name`) dos links por pessoa dessas páginas que ainda não têm.
# Página que já tem nome não é tocada. Rodar de novo não muda nada.
#
# Conta que falha não derruba o deploy: é desfeita sozinha, vai para o log (`[booking_short_name_backfill]`) e para o
# resumo abaixo. As páginas dela seguem com o link comprido e ganham o endereço quando alguém as abrir em Editar.
#
# A regra do nome é a mesma da tela, e por isso mora no serviço (`Crm::BookingV2::ShortNameBackfill`), que tem spec.
# Se um dia o serviço sair do código, esta migration vira um aviso e não quebra quem monta um banco do zero (banco
# novo não tem página para preencher).
#
# `down` não apaga nada, de propósito: depois do deploy os links curtos já foram copiados e divulgados, e não há como
# distinguir o nome que esta migration deu do nome que a pessoa escolheu. Para desfazer à mão, ver
# `docs/audit/agendamento-endereco-por-conta-1299.md`.
class BackfillBookingShortNames < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  SERVICE = 'Crm::BookingV2::ShortNameBackfill'.freeze
  # Carregados antes da migration de esquema: as colunas e a tabela novas ainda não estão na memória deles.
  MODELS = %w[Crm::AgentBookingProfile Crm::BookingAccountAddress].freeze

  def up
    service = SERVICE.safe_constantize
    return say("#{SERVICE} não existe mais: nada a preencher") if service.nil?

    MODELS.filter_map(&:safe_constantize).each(&:reset_column_information)
    result = service.run
    say "contas alteradas: #{result.accounts}, páginas com nome novo: #{result.pages}, contas com falha: #{result.failed_account_ids.inspect}"
  end

  def down; end
end
