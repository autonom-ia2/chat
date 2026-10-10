FactoryBot.define do
  factory :brand_kit do
    account
    sequence(:name) { |n| "Marca #{n}" }
    appearance do
      {
        palettes: {
          light: { primary: '#c8102e', accent: '#0ab9d1', ink: '#0b243f', muted: '#4b5563', surface: '#ffffff',
                   background: '#ffffff', tint: '#fae7ea', band: '#0b243f' },
          dark: { primary: '#ff1f2d', accent: '#0ab9d1', ink: '#ffffff', muted: '#c9d1da', surface: '#1e3550',
                  background: '#0b243f', tint: '#3a2a40', band: '#0b243f' }
        },
        site_palette: { primary: '#ff1f2d', accent: '#0ab9d1', ink: '#ffffff', muted: '#c9d1da',
                        surface: '#1e3550', background: '#0b243f', tint: '#3a2a40' },
        typography: { heading_font: 'MuseoModerno', body_font: 'Roboto' },
        social_links: [{ network: 'linkedin', url: 'https://www.linkedin.com/company/hub2you-insurtech' }],
        footer: { company_name: 'Hub2You', address: 'Av. Paulista, 1000 - São Paulo/SP' }
      }
    end
  end

  factory :brand_import_job do
    account
    url { 'https://hub2you.ai/' }
  end
end
