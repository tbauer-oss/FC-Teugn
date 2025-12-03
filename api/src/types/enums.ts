export const Role = {
  PARENT: 'PARENT',
  COACH: 'COACH',
} as const;

export type Role = (typeof Role)[keyof typeof Role];

export const RSVPStatus = {
  YES: 'YES',
  NO: 'NO',
  MAYBE: 'MAYBE',
} as const;

export type RSVPStatus = (typeof RSVPStatus)[keyof typeof RSVPStatus];
