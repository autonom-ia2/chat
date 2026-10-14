namespace :autonomia do
  namespace :whatsapp_proxy do
    # Uso: bundle exec rails "autonomia:whatsapp_proxy:importar[/caminho/webshare_assignments.json,hubsegs]"
    # O segundo argumento é o motor desta stack (primeira palavra do campo engine: hubsegs ou autonomia).
    # Funciona com WHATSAPP_PROXY_ENABLED desligada; a conta vem da sessão no banco e o plano do campo `plano`.
    desc 'Importa as atribuições de proxy da Webshare postas à mão (#1516). Idempotente; exige WEBSHARE_API_KEY.'
    task :importar, %i[arquivo engine] => :environment do |_task, args|
      abort('[whatsapp_proxy][importar] informe [arquivo,engine]') if args[:arquivo].blank? || args[:engine].blank?
      abort('[whatsapp_proxy][importar] WEBSHARE_API_KEY ausente') unless Webshare::Client.new.configured?

      entries = JSON.parse(File.read(args[:arquivo]))
      abort('[whatsapp_proxy][importar] o arquivo precisa ser uma lista JSON') unless entries.is_a?(Array)

      result = WhatsappProxy::Importer.new(entries: entries, engine: args[:engine]).perform
      puts "[whatsapp_proxy][importar][done] imported=#{result.imported} unchanged=#{result.unchanged} skipped=#{result.skipped}"
    end

    # Uso: bundle exec rails "autonomia:whatsapp_proxy:migrar[5511999999999]" — uma sessão por vez, com o recurso ligado.
    desc 'Põe proxy numa sessão existente sem atribuição (#1516): confere o /timelock, troca e confere; falhou, volta.'
    task :migrar, %i[sessao] => :environment do |_task, args|
      abort('[whatsapp_proxy][migrar] informe [sessao]') if args[:sessao].blank?

      result = WhatsappProxy::Migrator.new.call(args[:sessao].strip)
      puts "[whatsapp_proxy][migrar] session=#{args[:sessao].strip} #{result.outcome}: #{result.detail}"
      abort('[whatsapp_proxy][migrar] não migrou') unless result.outcome == :applied
    end

    # Uso: bundle exec rails "autonomia:whatsapp_proxy:liberar_quarentena[10.0.0.1]"
    desc 'Tira um IP da quarentena do proxy do WhatsApp (#1516) antes das 24 h.'
    task :liberar_quarentena, %i[ip] => :environment do |_task, args|
      abort('[whatsapp_proxy][liberar_quarentena] informe [ip]') if args[:ip].blank?

      removed = WhatsappProxy::Quarantine.release!(args[:ip].strip)
      puts "[whatsapp_proxy][liberar_quarentena] ip=#{args[:ip].strip} liberados=#{removed}"
    end
  end
end
