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
  end
end
