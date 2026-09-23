import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Dayshift',
  description: 'a quieter way to keep up with everything',
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
