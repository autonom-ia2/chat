import {
  hybridRecoveryNoteKey,
  hybridRecoveryHeaderKey,
} from '../hybridRecovery.js';

describe('hybridRecoveryNoteKey', () => {
  it('maps each recovery state to its notice', () => {
    expect(hybridRecoveryNoteKey({ hybridRecovery: 'pending' })).toBe(
      'CONVERSATION.HYBRID_RECOVERY.PENDING'
    );
    expect(hybridRecoveryNoteKey({ hybridRecovery: 'recovered' })).toBe(
      'CONVERSATION.HYBRID_RECOVERY.RECOVERED'
    );
    expect(hybridRecoveryNoteKey({ hybridRecovery: 'failed' })).toBe(
      'CONVERSATION.HYBRID_RECOVERY.FAILED'
    );
  });

  it('uses the media notice when the message had media', () => {
    expect(
      hybridRecoveryNoteKey({
        hybridRecovery: 'failed',
        hybridRecoveryReason: 'media',
      })
    ).toBe('CONVERSATION.HYBRID_RECOVERY.MEDIA');
  });

  it('returns null for messages that did not go through recovery', () => {
    expect(hybridRecoveryNoteKey({})).toBeNull();
    expect(hybridRecoveryNoteKey(undefined)).toBeNull();
    expect(hybridRecoveryNoteKey({ hybridRecovery: 'media' })).toBeNull();
  });
});

describe('hybridRecoveryHeaderKey', () => {
  it('maps the template header file to its notice', () => {
    expect(hybridRecoveryHeaderKey({ hybridRecoveryHeader: 'image' })).toBe(
      'CONVERSATION.HYBRID_RECOVERY.HEADER_IMAGE'
    );
    expect(hybridRecoveryHeaderKey({ hybridRecoveryHeader: 'media' })).toBe(
      'CONVERSATION.HYBRID_RECOVERY.HEADER_MEDIA'
    );
  });

  it('leaves the notice to the media message (only the caption came)', () => {
    expect(
      hybridRecoveryHeaderKey({
        hybridRecovery: 'failed',
        hybridRecoveryReason: 'media',
        hybridRecoveryHeader: 'image',
      })
    ).toBeNull();
  });

  it('returns null without a header file', () => {
    expect(hybridRecoveryHeaderKey({ hybridRecovery: 'recovered' })).toBeNull();
    expect(hybridRecoveryHeaderKey(undefined)).toBeNull();
  });
});
