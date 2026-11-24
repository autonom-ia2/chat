import { journeyCampaignsAPI } from '../campaignJourneyAudiences';

// #3099: com anexo (WhatsApp API), a campanha vai em multipart; as duas versões levam objetos dentro de objetos.
describe('journeyCampaignsAPI.createWithFile', () => {
  const post = vi.fn();
  beforeEach(() => {
    window.axios = { post };
    post.mockResolvedValue({});
  });

  it('manda cada campo aninhado com o caminho inteiro', async () => {
    const file = new File(['x'], 'foto.jpg', { type: 'image/jpeg' });
    await journeyCampaignsAPI.createWithFile({
      campaign_import_id: 5,
      channel: 'whatsapp_api',
      campaign: {
        title: 'Renovação',
        media_file: file,
        variable_defaults: { 'contact.first_name': 'cliente' },
        duas_versoes: {
          criterio: 'respostas',
          divisao: 50,
          segunda: {
            message_body: 'Oi!',
            variable_defaults: { 'contact.first_name': 'você' },
          },
        },
        scheduled_at: null,
      },
    });

    const formData = post.mock.calls[0][1];
    expect(Object.fromEntries(formData.entries())).toEqual({
      campaign_import_id: '5',
      channel: 'whatsapp_api',
      'campaign[title]': 'Renovação',
      'campaign[media_file]': expect.any(File),
      'campaign[variable_defaults][contact.first_name]': 'cliente',
      'campaign[duas_versoes][criterio]': 'respostas',
      'campaign[duas_versoes][divisao]': '50',
      'campaign[duas_versoes][segunda][message_body]': 'Oi!',
      'campaign[duas_versoes][segunda][variable_defaults][contact.first_name]':
        'você',
    });
  });
});
