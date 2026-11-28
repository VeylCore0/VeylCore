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

export type AppProps = { route?: string };

/** Built-in apps this UI implements. The server decides which are installed; apps missing here are never shown. */
export const VIEWS: Record<string, ComponentType<AppProps>> = {
  phone: PhoneApp, messages: MessagesApp, contacts: ContactsApp, settings: SettingsApp,
  mail: MailApp, store: StoreApp, calculator: CalculatorApp, clock: ClockApp,
  notes: NotesApp, bank: BankApp, garage: GarageApp, market: MarketApp, flock: FlockApp,
};
