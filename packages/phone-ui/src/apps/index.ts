import type { ComponentType } from 'react';
import { PhoneApp } from './PhoneApp';
import { MessagesApp } from './Messages';
import { ContactsApp } from './Contacts';
import { SettingsApp } from './Settings';
import { MailApp } from './Mail';
import { StoreApp } from './Store';
import { CalculatorApp } from './Calculator';
import { ClockApp } from './Clock';
import { NotesApp } from './Notes';
import { BankApp } from './Bank';
import { GarageApp } from './Garage';
import { MarketApp } from './Market';
import { FlockApp } from './Flock';
import { MapsApp } from './Maps';
import { ServicesApp } from './Services';
import { VoicemailApp } from './Voicemail';
import { CameraApp } from './Camera';
import { JobsApp } from './Jobs';
import { BillsApp } from './Bills';
import { MusicApp } from './Music';
import { NewsApp } from './News';
import { RacingApp } from './Racing';

export type AppProps = { route?: string };

/** Built-in apps this UI implements. The server decides which are installed; apps missing here are never shown. */
export const VIEWS: Record<string, ComponentType<AppProps>> = {
  phone: PhoneApp, messages: MessagesApp, contacts: ContactsApp, settings: SettingsApp,
  mail: MailApp, store: StoreApp, calculator: CalculatorApp, clock: ClockApp,
  notes: NotesApp, bank: BankApp, garage: GarageApp, market: MarketApp, flock: FlockApp,
  maps: MapsApp, services: ServicesApp, voicemail: VoicemailApp,
  camera: CameraApp, jobs: JobsApp, bills: BillsApp, music: MusicApp, news: NewsApp, racing: RacingApp,
};
