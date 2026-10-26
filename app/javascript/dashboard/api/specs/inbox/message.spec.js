import messageAPI, { buildCreatePayload } from '../../inbox/message';
import ApiClient from '../../ApiClient';

describe('#ConversationAPI', () => {
  it('creates correct instance', () => {
    expect(messageAPI).toBeInstanceOf(ApiClient);
    expect(messageAPI).toHaveProperty('get');
    expect(messageAPI).toHaveProperty('show');
    expect(messageAPI).toHaveProperty('create');
    expect(messageAPI).toHaveProperty('update');
    expect(messageAPI).toHaveProperty('delete');
    expect(messageAPI).toHaveProperty('getPreviousMessages');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#getPreviousMessages', () => {
      messageAPI.getPreviousMessages({
        conversationId: 12,
        before: 4573,
      });
      expect(axiosMock.get).toHaveBeenCalledWith(
        `/api/v1/conversations/12/messages`,
        {
          params: {
            before: 4573,
          },
        }
      );
    });
  });
  describe('#buildCreatePayload', () => {
    it('builds form payload if file is available', () => {
      const formPayload = buildCreatePayload({
        message: 'test content',
        echoId: 12,
        isPrivate: true,
        contentAttributes: { in_reply_to: 12 },
        files: [new Blob(['test-content'], { type: 'application/pdf' })],
      });
      expect(formPayload).toBeInstanceOf(FormData);
      expect(formPayload.get('content')).toEqual('test content');
      expect(formPayload.get('echo_id')).toEqual('12');
      expect(formPayload.get('private')).toEqual('true');
      expect(formPayload.get('cc_emails')).toEqual('');
      expect(formPayload.get('bcc_emails')).toEqual('');
      expect(formPayload.get('content_attributes')).toEqual(
        '{"in_reply_to":12}'
      );
    });

    it('builds object payload if file is not available', () => {
      expect(
        buildCreatePayload({
          message: 'test content',
          isPrivate: false,
          echoId: 12,
          contentAttributes: { in_reply_to: 12 },
        })
      ).toEqual({
        content: 'test content',
        private: false,
        echo_id: 12,
        content_attributes: { in_reply_to: 12 },
        cc_emails: '',
        bcc_emails: '',
        to_emails: '',
        template_params: undefined,
      });
    });

    it('appends is_voice_message when isVoiceMessage is true', () => {
      const formPayload = buildCreatePayload({
        message: 'voice message',
        echoId: 42,
        isPrivate: false,
        files: [new Blob(['audio-data'], { type: 'audio/ogg' })],
        isVoiceMessage: true,
      });
      expect(formPayload).toBeInstanceOf(FormData);
      expect(formPayload.get('is_voice_message')).toEqual('true');
    });

    it('appends document_indexes for the attachments sent as documents (#1702)', () => {
      const formPayload = buildCreatePayload({
        message: 'foto como documento',
        echoId: 44,
        isPrivate: false,
        files: [
          new Blob(['png'], { type: 'image/png' }),
          new Blob(['png'], { type: 'image/png' }),
        ],
        documentIndexes: [1],
      });
      expect(formPayload.getAll('document_indexes[]')).toEqual(['1']);
      expect(
        buildCreatePayload({
          echoId: 45,
          files: [new Blob(['png'], { type: 'image/png' })],
        }).getAll('document_indexes[]')
      ).toEqual([]);
    });

    it('sends ficar_com_a_conversa and the owner the screen saw only when decided (#2067)', () => {
      const json = buildCreatePayload({
        message: 'oi',
        ficarComAConversa: true,
        ficarComAConversaDe: { tipo: 'pessoa', id: 9 },
      });
      expect(json.ficar_com_a_conversa).toBe(true);
      expect(json.ficar_com_a_conversa_de).toEqual({ tipo: 'pessoa', id: 9 });
      expect(
        buildCreatePayload({ message: 'oi' }).ficar_com_a_conversa
      ).toBeUndefined();

      const files = [new Blob(['png'], { type: 'image/png' })];
      const form = buildCreatePayload({
        files,
        ficarComAConversa: false,
        ficarComAConversaDe: { tipo: 'pessoa', id: 9 },
      });
      expect(form.get('ficar_com_a_conversa')).toBe('false');
      expect(form.get('ficar_com_a_conversa_de[tipo]')).toBe('pessoa');
      expect(form.get('ficar_com_a_conversa_de[id]')).toBe('9');
      const daIa = buildCreatePayload({
        files,
        ficarComAConversa: true,
        ficarComAConversaDe: { tipo: 'ia' },
      });
      expect(daIa.get('ficar_com_a_conversa_de[tipo]')).toBe('ia');
      expect(daIa.get('ficar_com_a_conversa_de[id]')).toBeNull();
      expect(
        buildCreatePayload({ files }).get('ficar_com_a_conversa')
      ).toBeNull();
    });

    it('sends reabrir_ao_escrever only when asked (#2216)', () => {
      expect(
        buildCreatePayload({ message: 'oi', reabrirAoEscrever: true })
          .reabrir_ao_escrever
      ).toBe(true);
      expect(buildCreatePayload({ message: 'oi' })).not.toHaveProperty(
        'reabrir_ao_escrever'
      );

      const files = [new Blob(['png'], { type: 'image/png' })];
      expect(
        buildCreatePayload({ files, reabrirAoEscrever: true }).get(
          'reabrir_ao_escrever'
        )
      ).toBe('true');
      expect(
        buildCreatePayload({ files }).get('reabrir_ao_escrever')
      ).toBeNull();
    });

    it('does not append is_voice_message when isVoiceMessage is false', () => {
      const formPayload = buildCreatePayload({
        message: 'regular audio',
        echoId: 43,
        isPrivate: false,
        files: [new Blob(['audio-data'], { type: 'audio/ogg' })],
        isVoiceMessage: false,
      });
      expect(formPayload).toBeInstanceOf(FormData);
      expect(formPayload.get('is_voice_message')).toBeNull();
    });
  });
});
