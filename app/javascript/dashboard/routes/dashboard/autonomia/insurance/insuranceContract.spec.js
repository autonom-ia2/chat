import { describe, it, expect } from 'vitest';
import {
  CONNECTION_STATES,
  STATE_TONE,
  buildConnection,
  isConnectedState,
  isTransientState,
  maskUsername,
} from './insuranceContract';

describe('insuranceContract', () => {
  it('maps every connection state to a visual tone', () => {
    Object.values(CONNECTION_STATES).forEach(state => {
      expect(STATE_TONE[state]).toBeTruthy();
    });
  });

  it('treats only provisioning/authenticating/discovering as transient', () => {
    expect(isTransientState(CONNECTION_STATES.PROVISIONING)).toBe(true);
    expect(isTransientState(CONNECTION_STATES.AUTHENTICATING)).toBe(true);
    expect(isTransientState(CONNECTION_STATES.DISCOVERING)).toBe(true);
    expect(isTransientState(CONNECTION_STATES.READY)).toBe(false);
    expect(isTransientState(CONNECTION_STATES.HUMAN_REQUIRED)).toBe(false);
  });

  it('treats ready and degraded as connected, never human_required or offline', () => {
    expect(isConnectedState(CONNECTION_STATES.READY)).toBe(true);
    expect(isConnectedState(CONNECTION_STATES.DEGRADED)).toBe(true);
    expect(isConnectedState(CONNECTION_STATES.HUMAN_REQUIRED)).toBe(false);
    expect(isConnectedState(CONNECTION_STATES.OFFLINE)).toBe(false);
  });

  it('masks the username keeping only two leading characters and the domain', () => {
    expect(maskUsername('corretora@exemplo.com.br')).toBe(
      'co*******@exemplo.com.br'
    );
    expect(maskUsername('ab')).toBe('ab**');
    expect(maskUsername('')).toBe('');
  });

  it('builds a not_configured connection without any credential field', () => {
    const connection = buildConnection();
    expect(connection.status).toBe(CONNECTION_STATES.NOT_CONFIGURED);
    expect(connection.capabilities).toEqual([]);
    expect(Object.keys(connection)).not.toContain('password');
    expect(Object.keys(connection)).not.toContain('username');
  });
});
