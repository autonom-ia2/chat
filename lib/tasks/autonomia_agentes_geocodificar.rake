# #1479 F3: preenche a coordenada dos locais presenciais das páginas que já existiam antes da flag
# `agentes_enviar_local_e_contato`. Só ENFILEIRA o `Crm::BookingV2::GeocodificarLocaisJob`, uma vez por página nova com
# endereço sem coordenada, nas contas pedidas e ligadas (a Fase 2 e a flag). Nada é gravado aqui, e a saída só leva ids.
#   bundle exec rails "autonomia:agentes:geocodificar_paginas[1,16,18]"
namespace :autonomia do
  namespace :agentes do
    desc 'Enfileira a coordenada dos locais presenciais das páginas de agendamento das contas pedidas (#1479 F3)'
    task :geocodificar_paginas, [:account_ids] => :environment do |_task, args|
      ids = [args[:account_ids], *args.extras].compact.filter_map { |valor| Integer(valor.to_s.strip, exception: false) }
      abort 'Informe as contas: autonomia:agentes:geocodificar_paginas[1,16,18]' if ids.empty?

      Account.where(id: ids).find_each do |account|
        next puts("[geocodificar] conta=#{account.id} desligada") unless Autonomia::Agents::Tools::Native::CartaoDaPagina.ligado?(account)

        paginas = account.crm_agent_booking_profiles.new_pages.select { |pagina| pagina.enderecos_sem_coordenada.any? }
        paginas.each { |pagina| Crm::BookingV2::GeocodificarLocaisJob.perform_later(pagina.id) }
        puts "[geocodificar] conta=#{account.id} paginas=#{paginas.map(&:id).join(',')}"
      end
    end
  end
end
