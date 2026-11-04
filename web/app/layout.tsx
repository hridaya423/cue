import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://cue.hridya.tech"),
  title: "Cue: Mac clipboard that pastes the part that fits a field",
  description:
    "Cue is a Mac clipboard. It reads the field you are in and pastes only the part of your copy that fits, like the email from a message. Needs macOS 15.",
  authors: [{ name: "Hridya Agrawal", url: "https://www.hridya.tech" }],
  creator: "Hridya Agrawal",
  alternates: { canonical: "/" },
  icons: { icon: "/favicon.svg", apple: "/apple-touch-icon.png" },
  openGraph: {
    type: "website",
    url: "/",
    siteName: "Cue",
    title: "Cue: Mac clipboard that pastes the part that fits a field",
    description: "A Mac clipboard that reads the field you are in and pastes only the part of your copy that fits.",
    images: "/og.png",
  },
  twitter: {
    card: "summary_large_image",
    title: "Cue: Mac clipboard that pastes the part that fits a field",
    description: "A Mac clipboard that reads the field you are in and pastes only the part of your copy that fits.",
    images: "/og.png",
  },
};

export const viewport: Viewport = { colorScheme: "only light", themeColor: "#2040e6" };

const boot = `document.documentElement.classList.add('js');(function(){var seen=false;try{seen=sessionStorage.getItem('cue-intro')==='1'}catch(e){}if(/^\\/(index\\.html)?$/.test(location.pathname)&&!matchMedia('(prefers-reduced-motion: reduce)').matches&&(/[?&]intro\\b/.test(location.search)||!seen))document.documentElement.classList.add('is-intro')})()`;

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: boot }} />
        <link rel="preload" href="/fonts/geist-700.woff2" as="font" type="font/woff2" crossOrigin="" />
        <link rel="preload" href="/fonts/geist-500.woff2" as="font" type="font/woff2" crossOrigin="" />
      </head>
      <body>
        <a className="skip-link" href="#main">Skip to content</a>
        {children}
      </body>
    </html>
  );
}
