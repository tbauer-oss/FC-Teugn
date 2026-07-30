import { ConsentType } from '@prisma/client';

export type ConsentOption = {
  id: string;
  label: string;
  description?: string;
};

export type ConsentTemplateDefinition = {
  type: ConsentType;
  version: string;
  title: string;
  shortTitle: string;
  purpose: string;
  legalBasis: string;
  retention: string;
  risks?: string;
  options: ConsentOption[];
  explicit: boolean;
};

const VERSION = '2026-07-30.1';

export const consentTemplates: Record<ConsentType, ConsentTemplateDefinition> = {
  PHOTO: {
    type: ConsentType.PHOTO,
    version: VERSION,
    title: 'Einwilligung in Einzel- und Porträtaufnahmen',
    shortTitle: 'Einzelfotos',
    purpose:
      'Dokumentation des Vereinslebens, Mannschaftskommunikation und Öffentlichkeitsarbeit des FC Teugn e.V.',
    legalBasis: 'Art. 6 Abs. 1 Buchst. a DSGVO sowie §§ 22, 23 KUG',
    retention:
      'Bis zum Widerruf oder Wegfall des Zwecks; gesetzliche Nachweis- und Archivpflichten bleiben unberührt.',
    risks:
      'Bei einer Veröffentlichung im Internet können Aufnahmen weltweit abgerufen, kopiert, verändert und über Suchmaschinen dauerhaft auffindbar werden. Eine vollständige Löschung bei Dritten kann nicht garantiert werden.',
    options: [
      { id: 'APP_INTERNAL', label: 'Geschützter Mannschaftsbereich der App' },
      { id: 'CLUB_WEBSITE', label: 'Vereinswebsite' },
      { id: 'SOCIAL_MEDIA', label: 'Offizielle Social-Media-Kanäle des Vereins' },
      { id: 'PRESS', label: 'Lokale Presse und Vereinschronik' },
      { id: 'WITH_NAME', label: 'Namensnennung zusammen mit der Aufnahme' },
    ],
    explicit: false,
  },
  TEAM_PHOTO: {
    type: ConsentType.TEAM_PHOTO,
    version: VERSION,
    title: 'Einwilligung in Mannschafts- und Gruppenaufnahmen',
    shortTitle: 'Mannschaftsfotos',
    purpose:
      'Mannschaftsdokumentation, Vereinschronik und Öffentlichkeitsarbeit des FC Teugn e.V.',
    legalBasis: 'Art. 6 Abs. 1 Buchst. a DSGVO sowie §§ 22, 23 KUG',
    retention:
      'Bis zum Widerruf oder Wegfall des Zwecks; bereits gedruckte Vereinschroniken und rechtmäßige Veröffentlichungen bleiben unberührt.',
    risks:
      'Internetveröffentlichungen können weltweit gespeichert und weiterverbreitet werden. Eine vollständige Entfernung aus Suchmaschinen, Archiven oder Kopien Dritter ist nicht garantiert.',
    options: [
      { id: 'APP_INTERNAL', label: 'Geschützter Mannschaftsbereich der App' },
      { id: 'CLUB_WEBSITE', label: 'Vereinswebsite' },
      { id: 'SOCIAL_MEDIA', label: 'Offizielle Social-Media-Kanäle des Vereins' },
      { id: 'PRESS', label: 'Lokale Presse und Vereinschronik' },
      { id: 'WITH_TEAM_LIST', label: 'Zuordnung zu Mannschaft und Saison' },
    ],
    explicit: false,
  },
  TRANSPORT: {
    type: ConsentType.TRANSPORT,
    version: VERSION,
    title: 'Erlaubnis zur Mitfahrt bei Vereinsfahrten',
    shortTitle: 'Mitfahrten',
    purpose:
      'Organisation freiwilliger Fahrgemeinschaften zu Training, Spielen, Turnieren und Vereinsveranstaltungen.',
    legalBasis:
      'Einwilligung nach Art. 6 Abs. 1 Buchst. a DSGVO; die Beförderung erfolgt als private Gefälligkeit, soweit nicht anders vereinbart.',
    retention:
      'Bis zum Widerruf, zum Ende der Mannschaftszugehörigkeit oder Wegfall des Zwecks.',
    options: [
      { id: 'COACHES', label: 'Mitfahrt bei Trainern und Vereinsverantwortlichen' },
      { id: 'KNOWN_PARENTS', label: 'Mitfahrt bei Eltern der eigenen Mannschaft' },
      { id: 'CLUB_ORGANIZED', label: 'Vom Verein organisierte Sammelfahrten' },
      { id: 'CONTACT_SHARED', label: 'Kontaktweitergabe ausschließlich zur Fahrtabstimmung' },
    ],
    explicit: false,
  },
  MEDICAL_DATA: {
    type: ConsentType.MEDICAL_DATA,
    version: VERSION,
    title: 'Ausdrückliche Einwilligung zur Verarbeitung von Gesundheitsdaten',
    shortTitle: 'Gesundheitsdaten',
    purpose:
      'Sichere Betreuung im Trainings- und Spielbetrieb, Berücksichtigung medizinischer Hinweise und Unterstützung im Notfall.',
    legalBasis: 'Art. 9 Abs. 2 Buchst. a in Verbindung mit Art. 6 Abs. 1 Buchst. a DSGVO',
    retention:
      'Bis zum Widerruf, zur Löschung des Spielerprofils oder Wegfall des Betreuungszwecks. Zugriffe werden auf berechtigte Personen begrenzt.',
    options: [
      { id: 'ALLERGIES', label: 'Allergien und Unverträglichkeiten' },
      { id: 'MEDICATION', label: 'Notwendige Medikamente und Einnahmehinweise' },
      { id: 'CONDITIONS', label: 'Relevante Erkrankungen und Belastungsgrenzen' },
      { id: 'EMERGENCY', label: 'Notfallhinweise und ärztliche Kontaktdaten' },
      { id: 'AUTHORIZED_STAFF', label: 'Zugriff für ausdrücklich berechtigte Trainer und Verantwortliche' },
    ],
    explicit: true,
  },
  COMMUNICATION: {
    type: ConsentType.COMMUNICATION,
    version: VERSION,
    title: 'Einwilligung in digitale Mannschaftskommunikation',
    shortTitle: 'Digitale Kommunikation',
    purpose:
      'Abstimmung von Terminen, Zu- und Absagen, kurzfristigen Änderungen und organisatorischen Vereinsinformationen.',
    legalBasis: 'Art. 6 Abs. 1 Buchst. a DSGVO',
    retention:
      'Bis zum Widerruf oder Ende der Mannschaftszugehörigkeit; technisch notwendige Kommunikation zur Vertragserfüllung bleibt davon getrennt.',
    options: [
      { id: 'APP_PUSH', label: 'Push-Nachrichten der FC-Teugn-App' },
      { id: 'EMAIL', label: 'E-Mail' },
      { id: 'SMS', label: 'SMS' },
      { id: 'MESSENGER', label: 'Vom Verein freigegebener Messenger / Mannschaftsgruppe' },
      { id: 'CONTACT_TEAM', label: 'Sichtbarkeit der Kontaktdaten für berechtigte Teammitglieder' },
    ],
    explicit: false,
  },
};

export function consentTemplate(type: ConsentType) {
  return consentTemplates[type];
}

export function publicConsentTemplates() {
  return Object.values(consentTemplates);
}
