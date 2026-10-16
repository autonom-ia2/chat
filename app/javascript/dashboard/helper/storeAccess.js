// Store validation is restricted to the platform role, not the account role.
export const canAccessStore = user => user?.type === 'SuperAdmin';
